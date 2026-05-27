from flask import Flask, jsonify, render_template, request, abort
import time
import random

app = Flask(__name__)

# In-memory storage for demonstrating Flask API functionality
tasks = [
    {
        "id": 1,
        "title": "Initialize premium Flask application scaffolding",
        "description": "Establish clean src/ and test/ folder structures.",
        "completed": True,
        "created_at": time.time() - 3600
    },
    {
        "id": 2,
        "title": "Design sleek modern Glassmorphism frontend",
        "description": "Utilize dark themes, glowing neon gradients, and responsive layouts.",
        "completed": False,
        "created_at": time.time() - 1800
    },
    {
        "id": 3,
        "title": "Add automated pytest test suite for all endpoints",
        "description": "Ensure code reliability using structured unit and integration tests.",
        "completed": False,
        "created_at": time.time() - 900
    },
    {
        "id": 4,
        "title": "Deploy application to production on port 19191",
        "description": "Verify environment variables and establish a reverse proxy or direct deployment.",
        "completed": False,
        "created_at": time.time()
    }
]

task_id_counter = 5
start_time = time.time()

@app.route('/')
def index():
    """Renders the primary web interface."""
    return render_template('index.html')

@app.route('/api/status', methods=['GET'])
def get_status():
    """
    Returns mock dynamic server metrics.
    Demonstrates background integration and JSON responses.
    """
    uptime_seconds = int(time.time() - start_time)
    
    # Generate realistic dynamic fluctuations
    cpu_usage = round(20.0 + random.uniform(-5.0, 15.0), 1)
    memory_usage = round(45.2 + random.uniform(-2.0, 2.0), 1)
    network_traffic = round(124.5 + random.uniform(-20.0, 40.0), 1)
    
    return jsonify({
        "status": "online",
        "uptime": uptime_seconds,
        "metrics": {
            "cpu_usage_pct": max(0.0, min(100.0, cpu_usage)),
            "memory_usage_pct": max(0.0, min(100.0, memory_usage)),
            "network_throughput_mbps": max(0.0, network_traffic),
            "database_connection": "healthy",
            "active_sessions": random.randint(3, 12)
        }
    })

@app.route('/api/tasks', methods=['GET'])
def get_tasks():
    """Retrieves all tasks, sorted by creation time descending."""
    return jsonify(sorted(tasks, key=lambda x: x['created_at'], reverse=True))

@app.route('/api/tasks', methods=['POST'])
def create_task():
    """Creates a new task. Requires JSON payload."""
    global task_id_counter
    if not request.json or 'title' not in request.json:
        abort(400, description="Missing required parameter 'title'.")
        
    title = request.json.get('title', '').strip()
    description = request.json.get('description', '').strip()
    
    if not title:
        abort(400, description="Title parameter cannot be empty.")
        
    new_task = {
        "id": task_id_counter,
        "title": title,
        "description": description,
        "completed": False,
        "created_at": time.time()
    }
    tasks.append(new_task)
    task_id_counter += 1
    
    return jsonify(new_task), 201

@app.route('/api/tasks/<int:task_id>', methods=['DELETE'])
def delete_task(task_id):
    """Deletes a task by its unique ID."""
    global tasks
    task_to_delete = next((task for task in tasks if task['id'] == task_id), None)
    if not task_to_delete:
        abort(404, description=f"Task with ID {task_id} not found.")
        
    tasks = [task for task in tasks if task['id'] != task_id]
    return jsonify({"success": True, "message": f"Task {task_id} successfully deleted."}), 200

@app.route('/api/tasks/<int:task_id>', methods=['PATCH'])
def toggle_task_completion(task_id):
    """Toggles task completed status."""
    task_to_update = next((task for task in tasks if task['id'] == task_id), None)
    if not task_to_update:
        abort(404, description=f"Task with ID {task_id} not found.")
        
    if not request.json or 'completed' not in request.json:
        abort(400, description="Missing completion status in body.")
        
    task_to_update['completed'] = bool(request.json['completed'])
    return jsonify(task_to_update), 200

@app.route('/feature1')
def feature1():
    """Feature 1: 早上提醒看股票。"""
    return '早上要看股票'

@app.route('/feature2')
def feature2():
    """Feature 2: 提醒要找下午上班的公司。"""
    return '要找下午上班的公司'

# Error Handler for API routes
@app.errorhandler(400)
def bad_request(error):
    return jsonify({"error": "Bad Request", "message": error.description}), 400

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Not Found", "message": error.description}), 404

@app.errorhandler(500)
def server_error(error):
    return jsonify({"error": "Internal Server Error", "message": "An unexpected error occurred."}), 500
