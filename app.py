#!/usr/bin/env python3
"""
Dataserver2 Collections Web Application
Provides authentication, settings management, and live log viewing
"""
import os
import secrets
import yaml
import logging
from datetime import datetime
from pathlib import Path
from functools import wraps
from flask import Flask, render_template, request, redirect, url_for, session, jsonify, Response, stream_with_context
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', secrets.token_hex(32))

# Configuration
BASE_DIR = Path(__file__).parent
CONFIG_FILE = BASE_DIR / 'web_config.yml'
LOG_FILE = BASE_DIR / 'app.log'

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


def load_config():
    """Load configuration from file"""
    if not CONFIG_FILE.exists():
        # Create default config
        default_config = {
            'authentication_enabled': False,
            'username': None,
            'password_hash': None,
            'api_key': None
        }
        save_config(default_config)
        return default_config
    
    with open(CONFIG_FILE, 'r') as f:
        return yaml.safe_load(f) or {}


def save_config(config):
    """Save configuration to file"""
    with open(CONFIG_FILE, 'w') as f:
        yaml.dump(config, f, default_flow_style=False)


def require_auth(f):
    """Decorator to require authentication"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        config = load_config()
        
        # Check if authentication is disabled
        if not config.get('authentication_enabled', False):
            return f(*args, **kwargs)
        
        # Check API key in header
        api_key = request.headers.get('X-Api-Key')
        if api_key and api_key == config.get('api_key'):
            return f(*args, **kwargs)
        
        # Check session for web login
        if not session.get('logged_in'):
            if request.headers.get('X-Api-Key'):
                return jsonify({'error': 'Invalid API key'}), 401
            return redirect(url_for('login'))
        
        return f(*args, **kwargs)
    return decorated_function


@app.route('/')
@require_auth
def index():
    """Home page"""
    config = load_config()
    return render_template('index.html', 
                         auth_enabled=config.get('authentication_enabled', False))


@app.route('/login', methods=['GET', 'POST'])
def login():
    """Login page"""
    config = load_config()
    
    # If auth is disabled, redirect to home
    if not config.get('authentication_enabled', False):
        return redirect(url_for('index'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if (username == config.get('username') and 
            config.get('password_hash') and
            check_password_hash(config.get('password_hash'), password)):
            session['logged_in'] = True
            session['username'] = username
            logger.info(f"User {username} logged in successfully")
            return redirect(url_for('index'))
        else:
            logger.warning(f"Failed login attempt for user {username}")
            return render_template('login.html', error='Invalid username or password')
    
    return render_template('login.html')


@app.route('/logout')
def logout():
    """Logout"""
    username = session.get('username', 'unknown')
    session.clear()
    logger.info(f"User {username} logged out")
    return redirect(url_for('login'))


@app.route('/settings', methods=['GET', 'POST'])
@require_auth
def settings():
    """Settings page for managing authentication"""
    config = load_config()
    message = None
    error = None
    
    if request.method == 'POST':
        action = request.form.get('action')
        
        if action == 'update_auth':
            # Update authentication settings
            enable_auth = request.form.get('enable_auth') == 'on'
            username = request.form.get('username', '').strip()
            password = request.form.get('password', '')
            
            if enable_auth:
                if not username or not password:
                    error = 'Username and password are required when authentication is enabled'
                else:
                    config['authentication_enabled'] = True
                    config['username'] = username
                    config['password_hash'] = generate_password_hash(password)
                    save_config(config)
                    message = 'Authentication settings updated successfully'
                    logger.info(f"Authentication enabled for user {username}")
            else:
                config['authentication_enabled'] = False
                save_config(config)
                message = 'Authentication disabled'
                logger.info("Authentication disabled")
        
        elif action == 'generate_api_key':
            # Generate new API key
            new_api_key = secrets.token_urlsafe(32)
            config['api_key'] = new_api_key
            save_config(config)
            message = f'New API key generated'
            logger.info("New API key generated")
        
        elif action == 'delete_api_key':
            # Delete API key
            config['api_key'] = None
            save_config(config)
            message = 'API key deleted'
            logger.info("API key deleted")
        
        # Reload config to show updated values
        config = load_config()
    
    return render_template('settings.html', 
                         config=config, 
                         message=message, 
                         error=error)


@app.route('/logs')
@require_auth
def logs():
    """Logs page"""
    return render_template('logs.html')


@app.route('/logs/stream')
@require_auth
def logs_stream():
    """Stream logs using Server-Sent Events"""
    def generate():
        # First, send existing log content
        if LOG_FILE.exists():
            with open(LOG_FILE, 'r') as f:
                # Get last 100 lines
                lines = f.readlines()
                for line in lines[-100:]:
                    yield f"data: {line}\n\n"
        
        # Then watch for new lines
        import time
        import subprocess
        
        # Use tail -f to follow the log file
        try:
            process = subprocess.Popen(
                ['tail', '-f', '-n', '0', str(LOG_FILE)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            for line in iter(process.stdout.readline, ''):
                if line:
                    yield f"data: {line}\n\n"
                time.sleep(0.1)
        except Exception as e:
            logger.error(f"Error streaming logs: {e}")
            yield f"data: Error streaming logs: {e}\n\n"
    
    return Response(stream_with_context(generate()), 
                   mimetype='text/event-stream',
                   headers={
                       'Cache-Control': 'no-cache',
                       'X-Accel-Buffering': 'no'
                   })


@app.route('/api/status')
@require_auth
def api_status():
    """API endpoint for status check"""
    return jsonify({
        'status': 'ok',
        'timestamp': datetime.utcnow().isoformat(),
        'authentication_enabled': load_config().get('authentication_enabled', False)
    })


@app.route('/api/collections')
@require_auth
def api_collections():
    """API endpoint to list collection files"""
    collections = []
    for yml_file in BASE_DIR.glob('*.yml'):
        if yml_file.stem not in ['web_config']:
            collections.append({
                'name': yml_file.stem,
                'filename': yml_file.name,
                'size': yml_file.stat().st_size,
                'modified': datetime.fromtimestamp(yml_file.stat().st_mtime).isoformat()
            })
    return jsonify({'collections': collections})


if __name__ == '__main__':
    logger.info("Starting Dataserver2 Collections Web Application")
    port = int(os.environ.get('PORT', 5000))
    host = os.environ.get('HOST', '0.0.0.0')
    app.run(host=host, port=port, debug=False)
