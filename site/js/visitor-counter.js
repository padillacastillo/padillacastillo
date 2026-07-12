// TODO: replace with the real API Gateway invoke URL once `terraform apply` outputs it
// (see terraform/visitor_counter.tf output "visitor_counter_api_url")
const VISITOR_COUNTER_API_URL = "https://REPLACE-ME.execute-api.us-east-1.amazonaws.com/count";

const counterEl = document.getElementById("visitor-count");

fetch(VISITOR_COUNTER_API_URL)
  .then(function (response) {
    if (!response.ok) {
      throw new Error("Request failed");
    }
    return response.json();
  })
  .then(function (data) {
    counterEl.textContent = data.count;
  })
  .catch(function () {
    counterEl.textContent = "—";
  });
