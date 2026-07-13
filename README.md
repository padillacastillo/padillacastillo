# padillacastillo.com: Cloud Resume Challenge

I built this project to get hands-on experience with AWS, using the [Cloud Resume Challenge](https://cloudresumechallenge.dev/) as a structured way to apply what I've been learning. This README focuses less on how the project works and more on the reasoning behind each decision, the kind of explanation I'd want to give in an interview.

## Architecture

```mermaid
flowchart TD
    Browser(["Browser"]) -->|HTTPS| CF["CloudFront<br/>CDN + TLS"]
    CF --> S3["S3 (private bucket)<br/>static HTML/CSS/JS"]
    CF --> APIGW["API Gateway<br/>HTTP API"]
    APIGW --> LAM["Lambda<br/>visitor_counter"]
    LAM --> DDB[("DynamoDB")]
    LAM --> SECMGR["Secrets Manager<br/>IP HMAC key"]
    S3 --> LP["padillacastillo.com<br/>landing page"]
    S3 --> RP["padillacastillo.com/resume<br/>resume page"]
    S3 --> CP["padillacastillo.com/contact<br/>contact page"]

    CP -->|form submit| CFAPIGW["API Gateway<br/>HTTP API"]
    CFAPIGW --> CFLAM["Lambda<br/>contact_form"]
    CFLAM --> SES["SES"]
    SES -->|email| Inbox(["Inbox"])

    GHA["GitHub Actions"] -->|deploy on push| TF["Terraform"]
    TF -.->|provisions| CF
    TF -.->|provisions| APIGW
    TF -.->|provisions| CFAPIGW

    classDef delivery fill:#0969da,stroke:#0969da,color:#fff
    classDef backend fill:#1a7f37,stroke:#1a7f37,color:#fff
    classDef pipeline fill:#8250df,stroke:#8250df,color:#fff

    class CF,S3,LP,RP,CP delivery
    class APIGW,LAM,DDB,SECMGR,CFAPIGW,CFLAM,SES,Inbox backend
    class GHA,TF pipeline
```

> **🔵 Delivery: how the site reaches your browser**
> - **S3** holds the static files, but it's locked down, so nobody can access it directly
> - **CloudFront** sits in front of it, handles HTTPS, and caches content close to wherever you're browsing from
> - **ACM** provides a free certificate, though it has to live in `us-east-1` no matter where the rest of this runs (CloudFront's one quirky requirement)
> - **Route 53** points `padillacastillo.com` at CloudFront

> **🟢 Backend: the visitor counter**
> - **API Gateway** is the public URL the counter hits
> - **Lambda** runs the Python that hashes the visitor's IP and increments the count
> - **DynamoDB** is where that number (and the set of already-seen visitor hashes) lives, since Lambda does not retain state between runs
> - **Secrets Manager** holds the key used to HMAC each visitor's IP before it's ever written to DynamoDB, so no raw IP is stored

> **🟢 Backend: the contact form** — a second, independent API Gateway/Lambda pair, not part of the visitor counter
> - **API Gateway** exposes a `POST /contact` route the form submits to, with CORS locked to the site's own origin and a low throttle limit (5 req/s) as a spam brake
> - **Lambda** validates the input and drops anything that trips the honeypot field before it ever reaches SES
> - **SES** sends the email; no database involved, since there's nothing to persist

> **🟣 Pipeline: how it gets built and shipped** (the dotted arrows above show this: it runs when I push code, not when someone visits the site)
> - **Terraform** defines every resource above as code, so nothing gets configured by hand in the console
> - **GitHub Actions** deploys on push, using a short-lived role instead of an AWS key sitting in GitHub secrets

## Why I made these choices

Grouped to match the diagram above. Click a question to expand.

### 🔵 Delivery

<details>
<summary>Why keep the S3 bucket private instead of turning on static website hosting?</summary>

- A public bucket lets anyone bypass CloudFront and hit S3 directly — no caching, no TLS.
- Origin Access Control lets CloudFront read from a private bucket instead, so S3 is never exposed to the internet.
</details>

### 🟢 Backend — visitor counter

<details>
<summary>Why count unique visitors instead of just incrementing on every page load?</summary>

- Incrementing on every load mostly measures my own refreshes while testing, not real traffic.
- The Lambda hashes each request's source IP and only increments the total the first time it sees that hash.
</details>

<details>
<summary>Why HMAC the IP instead of storing it directly, or just hashing it with SHA-256?</summary>

- Storing raw IPs forever is more permanent exposure than a public site's visitor count needs.
- A plain hash isn't real protection: IPv4 has only ~4.3 billion addresses, so an attacker can precompute a hash for every one and reverse any leaked hash in a lookup.
- HMAC keys the hash with a secret — held in Secrets Manager, never in code or Terraform state — so a leaked value can't be matched back to an IP without that key.
- The same IP still always produces the same HMAC, so dedup still works correctly.
</details>

<details>
<summary>Why keep visitor records forever instead of expiring them with a TTL?</summary>

- "Unique" here means unique for the life of the site, not per day — a TTL would let the same person get re-counted once it expires.
- Storage cost for a resume site's traffic is negligible either way.
</details>

### 🟢 Backend — contact form

<details>
<summary>Why a Lambda-backed contact form instead of a plain <code>mailto:</code> link?</summary>

- A `mailto:` link puts my email address in the page's HTML in plain text — exactly what spam bots scrape for.
- Routing through a form means the address never appears in the source; the browser only ever talks to an API Gateway URL.
- The Lambda rejects anything that fills in a honeypot field (hidden from real users, visible to bots that auto-fill everything).
- The API Gateway route has a low throttle limit, so even a scripted flood gets capped before it reaches my inbox.
- It's independent of the S3/CloudFront/Route 53 hosting work — SES only needs a verified email address, not a verified domain — so it didn't have to wait on that phase to exist.
</details>

### 🟣 Pipeline

<details>
<summary>Why GitHub Actions with OIDC instead of storing an AWS key in repo secrets?</summary>

- A key stored in GitHub secrets doesn't expire on its own — if it ever leaks, it's a standing problem.
- OIDC lets Actions assume a role for the duration of a single run, so there's no long-lived secret to leak in the first place.
</details>

<details>
<summary>Why does <code>.gitignore</code> skip the state files but keep the lock file?</summary>

- State can contain details I don't want sitting in git history, and it'll move to a remote backend eventually.
- The lock file pins exact provider versions, so `terraform init` on another machine, or in CI, produces the same build I tested locally.
</details>

### General

<details>
<summary>Why HTML instead of just uploading the PDF resume?</summary>

- The challenge is specifically about building a website, not hosting a file, so the resume became an actual page.
</details>


## Project structure
```
padillacastillo/
  site/
    index.html            landing page, served at padillacastillo.com/
    resume/index.html     resume page, served at padillacastillo.com/resume
    contact/index.html    contact form, served at padillacastillo.com/contact
    css/style.css         shared stylesheet
    js/contact.js         submits the contact form to API Gateway
    js/visitor-counter.js fetches the unique-visitor count and renders it
  lambda/
    visitor_counter.py    HMACs the visitor's IP, dedupes, increments the count
    contact_form.py       validates input, sends via SES, drops honeypot hits
  terraform/              every AWS resource above, as code
  .github/workflows/      test.yml (PR checks), deploy.yml (push to main)
```
