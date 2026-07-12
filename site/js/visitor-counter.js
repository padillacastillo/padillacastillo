const VISITOR_COUNTER_API_URL = "https://8tg1s8r8f0.execute-api.us-east-1.amazonaws.com/count";

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
