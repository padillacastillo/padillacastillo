const CONTACT_API_URL = "https://rc8s3wfo3i.execute-api.us-east-1.amazonaws.com/contact";

const form = document.getElementById("contact-form");
const submitBtn = document.getElementById("submit-btn");
const status = document.getElementById("form-status");

form.addEventListener("submit", async function (event) {
  event.preventDefault();

  const payload = {
    name: form.name.value.trim(),
    email: form.email.value.trim(),
    message: form.message.value.trim(),
    company: form.company.value, // honeypot; real users leave this empty
  };

  submitBtn.disabled = true;
  submitBtn.textContent = "Sending…";
  status.textContent = "";
  status.className = "form-status";

  // If the honeypot is filled, quietly pretend it worked without calling the API.
  if (payload.company) {
    setTimeout(function () {
      showSuccess();
    }, 600);
    return;
  }

  try {
    const response = await fetch(CONTACT_API_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error("Request failed");
    }

    showSuccess();
  } catch (err) {
    submitBtn.disabled = false;
    submitBtn.textContent = "Send message";
    status.textContent = "Something went wrong sending that — try again, or email me directly.";
    status.className = "form-status form-status-error";
  }
});

function showSuccess() {
  form.reset();
  submitBtn.textContent = "Sent";
  status.textContent = "Thanks — your message is on its way.";
  status.className = "form-status form-status-success";
}
