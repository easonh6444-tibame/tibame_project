import pytest
import sys
import os
import json

# Ensure the parent directory containing src is in the python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.app import app

@pytest.fixture
def client():
    """Configures the Flask application for testing."""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_home_page(client):
    """Verifies the home route renders successfully with correct components."""
    response = client.get('/')
    assert response.status_code == 200
    html_content = response.data.decode('utf-8')
    assert 'Nebula Dash' in html_content
    assert 'style.css' in html_content
    assert 'app.js' in html_content

def test_api_status(client):
    """Verifies the server status endpoint returns correctly formatted JSON metrics."""
    response = client.get('/api/status')
    assert response.status_code == 200
    data = json.loads(response.data)
    
    assert data['status'] == 'online'
    assert 'uptime' in data
    assert 'metrics' in data
    
    metrics = data['metrics']
    assert 'cpu_usage_pct' in metrics
    assert 'memory_usage_pct' in metrics
    assert 'network_throughput_mbps' in metrics
    assert metrics['database_connection'] == 'healthy'
    
    assert 0.0 <= metrics['cpu_usage_pct'] <= 100.0
    assert 0.0 <= metrics['memory_usage_pct'] <= 100.0

def test_api_get_tasks(client):
    """Verifies task retrieval API structure."""
    response = client.get('/api/tasks')
    assert response.status_code == 200
    data = json.loads(response.data)
    assert isinstance(data, list)
    assert len(data) >= 1
    
    # Check structure of the first task
    first_task = data[0]
    assert 'id' in first_task
    assert 'title' in first_task
    assert 'completed' in first_task
    assert 'created_at' in first_task

def test_api_crud_workflow(client):
    """Performs end-to-end CRUD checks: create, get, toggle, delete a task."""
    
    # 1. Create a Task
    new_task_payload = {
        "title": "Verify Flask application unit tests",
        "description": "Ensure code reliability using structured integration tests."
    }
    create_response = client.post(
        '/api/tasks',
        data=json.dumps(new_task_payload),
        content_type='application/json'
    )
    assert create_response.status_code == 201
    created_task = json.loads(create_response.data)
    assert created_task['title'] == new_task_payload['title']
    assert created_task['description'] == new_task_payload['description']
    assert created_task['completed'] is False
    task_id = created_task['id']

    # 2. Get and verify the task exists
    get_response = client.get('/api/tasks')
    data = json.loads(get_response.data)
    matching_task = next((t for t in data if t['id'] == task_id), None)
    assert matching_task is not None
    assert matching_task['title'] == new_task_payload['title']

    # 3. Toggle/Patch task completion status
    patch_response = client.patch(
        f'/api/tasks/{task_id}',
        data=json.dumps({"completed": True}),
        content_type='application/json'
    )
    assert patch_response.status_code == 200
    updated_task = json.loads(patch_response.data)
    assert updated_task['completed'] is True

    # 4. Delete the task
    delete_response = client.delete(f'/api/tasks/{task_id}')
    assert delete_response.status_code == 200
    delete_result = json.loads(delete_response.data)
    assert delete_result['success'] is True

    # 5. Confirm deletion
    get_after_delete_response = client.get('/api/tasks')
    data_after = json.loads(get_after_delete_response.data)
    deleted_task_check = next((t for t in data_after if t['id'] == task_id), None)
    assert deleted_task_check is None

def test_api_create_validation_failures(client):
    """Ensures input validation safeguards are working."""
    
    # Empty title
    payload_empty = {"title": "", "description": "Invalid payload"}
    response = client.post(
        '/api/tasks',
        data=json.dumps(payload_empty),
        content_type='application/json'
    )
    assert response.status_code == 400
    
    # Missing title field
    payload_missing = {"description": "Invalid payload"}
    response = client.post(
        '/api/tasks',
        data=json.dumps(payload_missing),
        content_type='application/json'
    )
    assert response.status_code == 400

def test_api_not_found_errors(client):
    """Ensures robust 404 response structure for invalid target IDs."""
    
    # Non-existent task delete
    response_delete = client.delete('/api/tasks/999999')
    assert response_delete.status_code == 404
    data_del = json.loads(response_delete.data)
    assert data_del['error'] == 'Not Found'
    
    # Non-existent task patch
    response_patch = client.patch(
        '/api/tasks/999999',
        data=json.dumps({"completed": True}),
        content_type='application/json'
    )
    assert response_patch.status_code == 404
    data_patch = json.loads(response_patch.data)
    assert data_patch['error'] == 'Not Found'

def test_feature1(client):
    """驗證 /feature1 回傳正確的繁體中文提示文字。"""
    response = client.get('/feature1')
    assert response.status_code == 200
    assert '早上要看股票' in response.data.decode('utf-8')

def test_feature2(client):
    """驗證 /feature2 回傳正確的繁體中文提示文字。"""
    response = client.get('/feature2')
    assert response.status_code == 200
    assert '要找下午上班的公司' in response.data.decode('utf-8')

