async function loadVisitorCount() {
    const counterEl = document.getElementById("visitor-count");

    try {
        const response = await fetch("https://dpkhuwhlj4.execute-api.us-east-1.amazonaws.com//visits");
        const data = await response.json();

        let bodyData = data;

        if (typeof data.body === "string") {
            bodyData = JSON.parse(data.body);
        }

        counterEl.textContent = bodyData.visits;
    } catch (error) {
        console.error("Error loading visitor count:", error);
        counterEl.textContent = "unavailable";
    }
}

loadVisitorCount();