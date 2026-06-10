import random
import time
from flask import Flask

app = Flask(__name__)

@app.route("/")
def index():
    # Simule une latence aléatoire
    duration = random.uniform(0.01, 0.6)
    time.sleep(duration)

    # Simule des erreurs aléatoires (~10%)
    if random.random() < 0.1:
        raise Exception("simulated error")

    return f"Hello from demo! (took {duration:.2f}s)\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
