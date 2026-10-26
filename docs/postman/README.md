# Live API in Postman

1. Open Postman, click **Import**, and choose `Mangao-WRS.postman_collection.json`.
2. Open the collection, go to **Variables**, and type the phone numbers and passwords of the accounts to use (the passwords are not saved in this file).
3. Run **1 Server and database > Health check** first. The free server can take about a minute to wake up.
4. Run a **Log in** request. It saves the token, so the other requests in that folder work right after.

Each response is the real JSON from the server on Render, read from the MySQL database on Aiven.
