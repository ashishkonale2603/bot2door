from flask import Flask, jsonify, request
from flask_cors import CORS
import threading
import time
import random
import os  # To get environment variables
import json  # To parse Gemini's response

# --- Import and configure Google Gemini ---
import google.generativeai as genai

# Get your API key from environment variables
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    print("WARNING: GEMINI_API_KEY environment variable not set.")

genai.configure(api_key=GEMINI_API_KEY)
# Initialize the model (use 'gemini-pro' as it's widely available)
gemini_model = genai.GenerativeModel("gemini-2.0-flash-lite")
# -----------------------------------------------

# Initialize the Flask application
app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# --- In-Memory State Management (Unchanged) ---
delivery_state = {
    "status": "idle",
    "otp": None,
    "cancelled": False
}

# --- Background Task (Unchanged) ---
def simulate_homeowner_response(company, info):
    """
    This function runs in a background thread. It simulates the time it takes
    to notify a homeowner and for them to reply with an OTP.
    """
    global delivery_state
    
    print("="*30)
    print("BACKEND: New Delivery Request")
    print(f"  Company: {company}")
    print(f"  Info: {info}")
    print("="*30)
    print("BACKEND: Notification sent to homeowner. Waiting for reply...")
    time.sleep(5)
    
    if delivery_state.get("cancelled", False):
        print("BACKEND: Delivery was cancelled. Aborting OTP generation.")
        return
        
    otp = str(random.randint(1000, 9999))
    delivery_state["status"] = "otp_ready"
    delivery_state["otp"] = otp
    print(f"BACKEND: Homeowner replied. OTP is {otp}.")

# --- NEW ENDPOINT: The "Brain" ---
@app.route('/understand-speech', methods=['POST'])
def understand_speech():
    """
    Receives raw text from Flutter, sends it to Gemini for extraction,
    and returns a clean JSON.
    """
    if not GEMINI_API_KEY:
        return jsonify({"status": "error", "message": "Backend AI not configured."}), 500

    data = request.get_json()
    if not data or 'raw_text' not in data:
        return jsonify({"status": "error", "message": "Missing raw_text."}), 400
        
    raw_text = data['raw_text']
    
    # This prompt is the most important part of the entire project
    prompt = f"""
    You are an assistant for a secure delivery box. A driver said: "{raw_text}"
    
    Your task is to extract the 'company_name' (e.g., "Amazon", "Blue Dart", "Dominos") 
    and the 'delivery_info' (e.g., "a package", "pizza for Mr. Sharma") from this text.
    
    Respond ONLY in valid JSON format, like this:
    {{"company_name": "...", "delivery_info": "..."}}
    
    If you cannot find a piece of information, set its value to "unknown".
    """
    
    try:
        # Ask Gemini to generate the content
        response = gemini_model.generate_content(prompt)
        
        # Clean up Gemini's response (it sometimes adds ```json ... ```)
        json_text = response.text.strip().replace("```json", "").replace("```", "")
        
        print(f"BACKEND: Gemini processed: {raw_text}")
        print(f"BACKEND: Gemini returned: {json_text}")
        
        # Try to parse the JSON to make sure it's valid before sending
        try:
            json.loads(json_text) # This just validates the JSON
        except json.JSONDecodeError:
            print("BACKEND ERROR: Gemini returned invalid JSON.")
            raise Exception("Invalid JSON from AI")

        # Send the *string* of the JSON back to Flutter
        return jsonify({
            "status": "ok", 
            "extracted_json": json_text 
        }), 200
        
    except Exception as e:
        print(f"BACKEND ERROR: Gemini processing failed: {e}")
        return jsonify({"status": "error", "message": f"AI processing failed: {e}"}), 500

# --- API Endpoints (All Unchanged) ---
@app.route('/start-delivery', methods=['POST'])
def start_delivery():
    global delivery_state
    
    data = request.get_json()
    if not data or 'company' not in data or 'info' not in data:
        return jsonify({"status": "error", "message": "Missing company or info."}), 400
        
    company = data['company']
    delivery_info = data['info']

    if delivery_state["status"] == "idle" or delivery_state["status"] == "completed":
        delivery_state["status"] = "waiting_for_otp"
        delivery_state["otp"] = None
        delivery_state["cancelled"] = False
        
        threading.Thread(target=simulate_homeowner_response, args=(company, delivery_info)).start()
        
        print("BACKEND: Received start delivery signal. Status: waiting_for_otp")
        return jsonify({"status": "ok", "message": "Homeowner notification process started."}), 200
    else:
        return jsonify({"status": "error", "message": "A delivery is already in progress."}), 409

@app.route('/check-status', methods=['GET'])
def check_status():
    global delivery_state
    print(f"BACKEND: Polled for status. Current status: {delivery_state['status']}")
    return jsonify({"status": delivery_state["status"]}), 200

@app.route('/speak-otp', methods=['GET'])
def speak_otp():
    global delivery_state
    
    if delivery_state["status"] == "otp_ready" and delivery_state["otp"] is not None:
        otp = delivery_state["otp"]
        spoken_otp = "... ".join(list(otp)) + "..."
        delivery_state["status"] = "completed"
        print(f"BACKEND: OTP {otp} provided. Status reset to completed.")
        return jsonify({"status": "ok", "spoken_otp": spoken_otp}), 200
    else:
        return jsonify({"status": "error", "message": "OTP is not ready or has already been provided."}), 404


@app.route('/cancel-delivery', methods=['POST'])
def cancel_delivery():
    global delivery_state
    
    if delivery_state["status"] == "waiting_for_otp":
        delivery_state["status"] = "idle"
        delivery_state["cancelled"] = True
        print("BACKEND: Received cancellation signal. Status reset to idle.")
        return jsonify({"status": "ok", "message": "Delivery cancelled."}), 200
    else:
        return jsonify({"status": "error", "message": "No active delivery to cancel."}), 400

# --- Main Entry Point ---
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
