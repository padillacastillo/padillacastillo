# Build plan: padillacastillo.com

Tracks what's left for the Cloud Resume Challenge, roughly in the order it needs to happen. Check items off as they're done, and update the Status section in `README.md` when a phase wraps.

Current state: `terraform/`, `lambda/`, `site/`, and `.github/workflows/` are all empty, and there isn't a first commit yet. Everything below starts from zero.

## Phase 0: Repo foundation
- [ ] Add a `.gitignore` to this repo (README already describes the intended rules: ignore `.terraform/` and `*.tfstate*`, keep `.terraform.lock.hcl`)
- [ ] Make the first commit
- [ ] Confirm the GitHub remote is set up and pushed

## Phase 1: Site content
- [ ] Write `site/index.html` (landing page)
- [ ] Write `site/resume/index.html` (resume page, replaces the PDF)
- [ ] Add CSS
- [ ] Add the visitor-counter JS that calls the API Gateway endpoint and renders the count

## Phase 2: Terraform for static hosting
- [ ] S3 bucket for site files (private, no public access)
- [ ] CloudFront distribution with Origin Access Control pointed at the bucket
- [ ] ACM certificate in `us-east-1` for `padillacastillo.com`
- [ ] Route 53 record pointing the domain at CloudFront
- [ ] Confirm HTTPS works end to end

## Phase 3: Terraform for the visitor counter backend
- [ ] DynamoDB table for the counter
- [ ] `lambda/visitor_counter.py`: read and increment the count
- [ ] Package and deploy the Lambda through Terraform
- [ ] API Gateway HTTP API in front of the Lambda
- [ ] IAM role scoped to just read/write on that one DynamoDB table
- [ ] Wire the frontend JS to the real API Gateway URL and confirm the count persists across refreshes

## Phase 4: CI/CD
- [ ] `.github/workflows/test.yml` — runs on PRs (`terraform validate`/`plan`, Lambda unit tests)
- [ ] `.github/workflows/deploy.yml` — runs on push to `main` (`terraform apply`, sync site files to S3, invalidate the CloudFront cache)
- [ ] Set up the GitHub OIDC provider and a deploy role scoped to this repo only
- [ ] Remove any long-lived AWS keys from GitHub secrets once OIDC is confirmed working

## Phase 5: Remote Terraform state
- [ ] S3 bucket for state
- [ ] DynamoDB table for state locking
- [ ] Migrate from local state with `terraform init -migrate-state`
- [ ] Confirm CI can run plan/apply against the remote backend

## Phase 6: Testing
- [ ] Unit tests for `visitor_counter.py` (mock DynamoDB with moto or similar)
- [ ] Confirm `test.yml` actually blocks a bad PR (test it with a deliberate failure)
- [ ] Manual pass: load the site, confirm the counter increments, confirm HTTPS, confirm the resume page renders correctly on mobile

## Phase 7: Polish
- [ ] Update the `README.md` Status section to reflect what's actually live
- [ ] Double check `.gitignore` isn't missing anything (`.terraform/`, state files, any local `.env`)
- [ ] Decide whether to drop the PDF from the repo root or keep it as a download link
- [ ] Add a link to the live site in `README.md`
