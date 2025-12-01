import subprocess
import time
import sys

def run_command(command, check_error=True):
    """Runs a shell command and returns its output."""
    try:
        result = subprocess.run(command, shell=True, check=check_error, capture_output=True, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {command}")
        print(f"Stdout: {e.stdout}")
        print(f"Stderr: {e.stderr}")
        sys.exit(1)
    except FileNotFoundError:
        print(f"Error: Command not found. Please ensure '{command.split()[0]}' is installed and in your PATH.")
        sys.exit(1)


def get_finch_vm_status():
    """Gets the status of the Finch VM."""
    print("Checking Finch VM status...")
    output = run_command("finch vm status", check_error=False) # Don't check error for status, as it might return non-zero if VM is not running
    print(f"Finch VM status output:\n{output}")
    return output

def is_finch_vm_running(status_output):
    """Checks if the Finch VM is running based on the status output."""
    return "Running" in status_output

def start_finch_vm():
    """Starts the Finch VM if it's not running."""
    print("Finch VM is not running. Attempting to start...")
    run_command("finch vm start")
    print("Finch VM start command issued. Waiting for it to become running...")

    # Wait for the VM to start, with a timeout
    max_retries = 10
    retry_delay_seconds = 10
    for i in range(max_retries):
        time.sleep(retry_delay_seconds)
        status = get_finch_vm_status()
        if is_finch_vm_running(status):
            print("Finch VM is now running.")
            return
        print(f"Finch VM still not running, retry {i+1}/{max_retries}...")
    
    print("Error: Finch VM did not start within the expected time.")
    sys.exit(1)

def main():
    # Check if finch is installed
    try:
        run_command("which finch", check_error=True)
    except SystemExit: # Catch the SystemExit from run_command if 'which finch' fails
        print("Error: 'finch' command not found. Please ensure Finch is installed and in your PATH.")
        sys.exit(1)

    status_output = get_finch_vm_status()
    if not is_finch_vm_running(status_output):
        start_finch_vm()
    else:
        print("Finch VM is already running.")

if __name__ == "__main__":
    main()
