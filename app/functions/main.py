from flask import Flask, request, jsonify
import numpy as np
from tensorflow.keras.models import load_model
import os

app = Flask(__name__)

# Lazy load the model
model = None

def get_model():
    global model
    if model is None:
        print("Loading the .keras model...")
        model_path = os.path.join(os.path.dirname(__file__), "best_bp_model.keras")
        model = load_model(model_path)
        print("Model loaded successfully.")
    return model

@app.route("/predict", methods=["POST"])
def predict_bp():
    try:
        print("Received a request...")
        # Parse the incoming JSON data
        data = request.get_json()
        if "ppg" not in data:
            return jsonify({"error": "Missing 'ppg' in request data"}), 400

        # Extract PPG signal and preprocess it
        print("Processing PPG signal...")
        ppg_signal = np.array(data["ppg"]).reshape(1, -1, 1)  # Reshape to [1, length, 1]

        # Load the model and make predictions
        print("Making predictions...")
        model = get_model()
        predictions = model.predict(ppg_signal)
        sbp, dbp = predictions[0]  # Assuming the model outputs [SBP, DBP]

        # Return the predictions as JSON
        print(f"Predictions: SBP={sbp}, DBP={dbp}")
        return jsonify({"sbp": float(sbp), "dbp": float(dbp)})
    except Exception as e:
        print(f"Error: {e}")
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)