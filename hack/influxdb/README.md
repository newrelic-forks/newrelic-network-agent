# InfluxDB with network-agent
This is a Docker compose setup that will create an InfluxDB stack and setup
network-agent to listen to a NetFlow generator.

# Run

`docker compose up`

This should launch all services. To view InfluxDB, visit http://localhost:8086.

User: `admin`
Password: `influxdb`
