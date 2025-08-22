# Crusoe Telemetry Agent
Crusoe telemetry agent is a vector.dev based agent for collecting telemetry data from Crusoe cloud resources.

# Installing Crusoe Telemetry Agent
ssh into your Crusoe nvidia GPU VM.

1. Download the agent setup script:
```
wget https://raw.githubusercontent.com/crusoecloud/crusoe-telemetry-agent/refs/heads/main/setup_crusoe_telemetry_agent.sh
```
2. Once the script is successfully downloaded. Once the script is successfully downloaded. Grant execute permission to the the script:
```
chmod +x setup_crusoe_telemetry_agent.sh
```
3. Run the installer:
```
sudo ./setup_crusoe_telemetry_agent.sh
```
While installing the script will prompt user to enter crusoe monitoring token. Paste the token created in above step.
Note: For enhanced security its a silent input, the token will not be displayed while pasting.
```
ubuntu@staging-gpu-vm-2:~$ sudo ./setup_crusoe_telemetry_agent.sh
Ensure docker installation.
Docker is already installed.
Ensuring wget is installed.
Create telemetry agent target directory.
Ensure NVIDIA dependencies exist.
Required NVIDIA dependencies are already installed.
Download DCGM exporter metrics config.
Download GPU Vector config.
Download GPU docker-compose file.
Fetching crusoe auth token.
Command: crusoe monitoring tokens create
Please enter the crusoe monitoring token:

```
4. After a successful installation you should see a message like this:
```
Setup Complete!
Run: 'sudo systemctl start crusoe-telemetry-agent' to start monitoring metrics.
Setup finished successfully!
```
5. Agent is managed via a systemd process. To start the agent, run this:
```
sudo systemctl start crusoe-telemetry-agent
```
6. This will download and start 2 docker containers, crusoe-dcgm-exporter & crusoe-vector. Give it around 30sec to download and start the containers, then check docker logs to verify if the container is running without errors:
```
docker container logs crusoe-vector
```
7. We should see logs like this with no Error:
```
2025-07-23T23:21:58.090868Z  INFO vector::app: Log level is enabled. level="info"
2025-07-23T23:21:58.091176Z  INFO vector::app: Loading configs. paths=["/etc/vector/vector.yaml"]
2025-07-23T23:21:58.106123Z  INFO vector::topology::running: Running healthchecks.
2025-07-23T23:21:58.106173Z  INFO vector::topology::builder: Healthcheck disabled.
2025-07-23T23:21:58.106182Z  INFO vector: Vector has started. debug="false" version="0.46.1" arch="x86_64" revision="9a19e8a 2025-04-14 18:36:30.707862743"
2025-07-23T23:21:58.106187Z  INFO vector::app: API is disabled, enable by setting `api.enabled` to `true` and use commands like `vector top`.
```
TA-DA!! crusoe telemetry agent is now successfully pushing metrics.
