import sys
import os

# Ensure the first_project directory is in the python path
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from src.app import app  # noqa: F401 – re-exported for Gunicorn (run:app)

if __name__ == '__main__':
    print("Starting Flask application on port 19191...")
    app.run(host='0.0.0.0', port=19191, debug=True)
