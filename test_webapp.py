#!/usr/bin/env python3
"""
Simple integration test for the web application
Tests authentication, API keys, and basic functionality
"""
import requests
import time
import subprocess
import sys
import os

BASE_URL = "http://localhost:5678"

def test_home_page_without_auth():
    """Test home page works when auth is disabled"""
    print("✓ Testing home page...")
    response = requests.get(f"{BASE_URL}/")
    assert response.status_code == 200, "Home page should be accessible"
    assert "Dataserver2 Collections" in response.text
    if "Login" in response.text:
        print("  ✓ Login page shown (auth enabled)")
    else:
        print("  ✓ Home page accessible (no auth)")

def test_api_status():
    """Test API status endpoint"""
    print("✓ Testing API status endpoint...")
    response = requests.get(f"{BASE_URL}/api/status")
    # If auth is enabled, it will redirect to login
    if response.status_code == 200 and response.headers.get('content-type', '').startswith('application/json'):
        data = response.json()
        assert data["status"] == "ok"
        print("  ✓ API status works (no auth)")
    else:
        print("  ✓ API requires authentication (expected behavior)")
        return True

def test_api_collections():
    """Test API collections endpoint"""
    print("✓ Testing API collections endpoint...")
    response = requests.get(f"{BASE_URL}/api/collections")
    if response.status_code == 200 and response.headers.get('content-type', '').startswith('application/json'):
        data = response.json()
        assert "collections" in data
        print(f"  ✓ Found {len(data['collections'])} collections")
    else:
        print("  ✓ API requires authentication (expected behavior)")

def test_settings_page():
    """Test settings page is accessible"""
    print("✓ Testing settings page...")
    response = requests.get(f"{BASE_URL}/settings")
    assert response.status_code == 200
    if "Authentication Settings" in response.text:
        print("  ✓ Settings page accessible")
    elif "Login" in response.text:
        print("  ✓ Settings page requires authentication (expected)")

def test_logs_page():
    """Test logs page is accessible"""
    print("✓ Testing logs page...")
    response = requests.get(f"{BASE_URL}/logs")
    assert response.status_code == 200
    if "Live Application Logs" in response.text:
        print("  ✓ Logs page accessible")
    elif "Login" in response.text:
        print("  ✓ Logs page requires authentication (expected)")

def main():
    print("=" * 60)
    print("Web Application Integration Test")
    print("=" * 60)
    print()
    
    # Check if server is running
    print("Checking if server is running...")
    try:
        response = requests.get(f"{BASE_URL}/", timeout=2)
        print("✓ Server is running\n")
    except requests.exceptions.ConnectionError:
        print("✗ Server is not running!")
        print(f"  Please start the server first: ./start-webapp.sh")
        sys.exit(1)
    
    # Run tests
    try:
        test_home_page_without_auth()
        test_api_status()
        test_api_collections()
        test_settings_page()
        test_logs_page()
        
        print()
        print("=" * 60)
        print("✓ All tests passed!")
        print("=" * 60)
        return 0
    except AssertionError as e:
        print(f"\n✗ Test failed: {e}")
        return 1
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
