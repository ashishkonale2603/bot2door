from flask import Flask, jsonify
from flask_cors import CORS
import threading
import time
import random

# Initialize the Flask application
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# --- In-Memory State Management ---
delivery_state = {
    "status": "idle",  # Can be 'idle', 'waiting_for_otp', 'otp_ready', 'completed'
    "otp": None,
    "cancelled": False  # Flag to stop the background thread
}

# --- Background Task to Simulate Homeowner Interaction ---
def simulate_homeowner_response():
    """
    This function runs in a background thread. It simulates the time it takes
    to notify a homeowner and for them to reply with an OTP.
    """
    global delivery_state
    
    print("BACKEND: Notification sent to homeowner. Waiting for reply...")
    time.sleep(5)
    
    # Check if the user cancelled while we were waiting
    if delivery_state.get("cancelled", False):
        print("BACKEND: Delivery was cancelled. Aborting OTP generation.")
        # The /cancel-delivery endpoint already reset the state
        return
        
    # Generate a random 4-digit OTP
    otp = str(random.randint(1000, 9999))
    
    # Update the state to indicate the OTP is ready
    delivery_state["status"] = "otp_ready"
    delivery_state["otp"] = otp
    print(f"BACKEND: Homeowner replied. OTP is {otp}.")

# --- API Endpoints ---
@app.route('/start-delivery', methods=['POST'])
def start_delivery():
    """
    Endpoint called by the Flutter app when the delivery person
    presses the "Start Delivery" button.
    """
    global delivery_state
    
    if delivery_state["status"] == "idle" or delivery_state["status"] == "completed":
        # Reset the state completely for a new delivery
        delivery_state["status"] = "waiting_for_otp"
        delivery_state["otp"] = None
        delivery_state["cancelled"] = False # Ensure flag is reset
        
        # Start the background task to get the OTP
        threading.Thread(target=simulate_homeowner_response).start()
        
        print("BACKEND: Received start delivery signal. Status: waiting_for_otp")
        return jsonify({"status": "ok", "message": "Homeowner notification process started."}), 200
    else:
        # Prevents starting a new delivery while one is in progress
        return jsonify({"status": "error", "message": "A delivery is already in progress."}), 409

@app.route('/check-status', methods=['GET'])
def check_status():
    """
    Endpoint for the Flutter app to poll to see if the OTP is ready yet.
    """
    global delivery_state
    print(f"BACKEND: Polled for status. Current status: {delivery_state['status']}")
    return jsonify({"status": delivery_state["status"]}), 200

@app.route('/speak-otp', methods=['GET'])
def speak_otp():
    """
    Once the status is 'otp_ready', the Flutter app calls this to get
    the OTP. The backend formats it for easy text-to-speech conversion.
    """
    global delivery_state
    
    if delivery_state["status"] == "otp_ready" and delivery_state["otp"] is not None:
        otp = delivery_state["otp"]
        spoken_otp = "... ".join(list(otp)) + "..." # e.g., "1... 2... 3... 4..."
        
        # Reset the state after providing the OTP
        delivery_state["status"] = "completed"
        
        print(f"BACKEND: OTP {otp} provided. Status reset to completed.")
        return jsonify({"status": "ok", "spoken_otp": spoken_otp}), 200
    else:
        return jsonify({"status": "error", "message": "OTP is not ready or has already been provided."}), 404

@app.route('/cancel-delivery', methods=['POST'])
def cancel_delivery():
    """
    Endpoint for the Flutter app to cancel an in-progress
    delivery request (one that is 'waiting_for_otp').
    """
    global delivery_state
    
    if delivery_state["status"] == "waiting_for_otp":
        delivery_state["status"] = "idle" # Reset status to idle
        delivery_state["cancelled"] = True # Set flag to stop the thread
        print("BACKEND: Received cancellation signal. Status reset to idle.")
        return jsonify({"status": "ok", "message": "Delivery cancelled."}), 200
    else:
        return jsonify({"status": "error", "message": "No active delivery to cancel."}), 400

# --- Main Entry Point ---
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)