# Azure VWAN Architecture - Quick Reference & Validation

## Network Address Space Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    NETWORK BREAKDOWN                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  VWAN Hub Network:        192.168.0.0/23                    │
│  ├─ App Gateway Subnet:   192.168.0.0/26                    │
│  ├─ Firewall Subnet:      192.168.0.0/26 (auto)             │
│  └─ Hub Reserved:         192.168.1.0/24                    │
│                                                              │
│  VNET 1 (App1):           10.0.0.0/16                       │
│  ├─ App Subnet:           10.0.1.0/24  (VM1: 10.0.1.10)     │
│  └─ Gateway Subnet:       10.0.0.0/27                       │
│                                                              │
│  VNET 2 (App2):           10.1.0.0/16                       │
│  ├─ App Subnet:           10.1.1.0/24  (VM2: 10.1.1.10)     │
│  └─ Gateway Subnet:       10.1.0.0/27                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Traffic Flow Reference

### **Flow 1: Internet User → App1**
```
Step 1: User hits http://AppGW-PublicIP/app1/
Step 2: Application Gateway receives on port 80
Step 3: AG checks URL path = "/app1/*"
Step 4: Route to Backend Pool = "backend-app1"
Step 5: Backend HTTP Setting = 8080
Step 6: Traffic sent to 10.0.1.10:8080 (VM1)
Step 7: VM1 web server responds
Step 8: Response sent back through AG
Step 9: User receives response
```

### **Flow 2: Internet User → App2**
```
Same as Flow 1, but:
Step 3: URL path = "/app2/*"
Step 4: Route to Backend Pool = "backend-app2"
Step 5: Backend HTTP Setting = 8081
Step 6: Traffic sent to 10.1.1.10:8081 (VM2)
```

### **Flow 3: VM1 → VM2 (East-West)**
```
Step 1: VM1 initiates connection to 10.1.1.10
Step 2: VM1 OS checks routing table (rt-app1)
Step 3: Route lookup: Destination = 10.1.0.0/16
Step 4: Matched route → Next Hop: Virtual Appliance (192.168.0.4)
Step 5: Packet sent to Firewall IP (192.168.0.4)
Step 6: Firewall receives packet
Step 7: Firewall Policy check:
        Source: 10.0.1.10 ✓ (in 10.0.0.0/16)
        Dest: 10.1.1.10 ✓ (in 10.1.0.0/16)
        Protocol: TCP/UDP ✓
        Action: ALLOW ✓
Step 8: Firewall forwards packet to 10.1.1.10
Step 9: VM2 receives packet
Step 10: VM2 responds
Step 11: Response follows reverse path back to VM1
```

### **Flow 4: VM1 → Internet (google.com)**
```
Step 1: VM1 initiates HTTPS to google.com:443
Step 2: VM1 DNS query (google.com)
        → Route to 8.8.8.8: Default route (0.0.0.0/0)
        → Next Hop: Virtual Appliance (192.168.0.4)
Step 3: DNS packet reaches Firewall
Step 4: Firewall Rule Check (allow-outbound-dns):
        Source: 10.0.1.10 ✓
        Protocol: UDP 53 ✓
        Action: ALLOW ✓
Step 5: Firewall forwards DNS query to 8.8.8.8
Step 6: DNS response: google.com = 142.250.x.x
Step 7: VM1 initiates HTTPS to 142.250.x.x:443
Step 8: HTTPS packet sent to Firewall (default route)
Step 9: Firewall Rule Check (allow-google-microsoft):
        Source: 10.0.1.10 ✓
        Dest FQDN: google.com ✓ (FQDN matched to 142.250.x.x)
        Protocol: HTTPS (TCP 443) ✓
        Action: ALLOW ✓
Step 10: Firewall SNAT: Changes source IP to Firewall Public IP
Step 11: Firewall forwards packet to google.com
Step 12: Google responds to Firewall Public IP
Step 13: Firewall reverses NAT and sends response to VM1
```

## Port Mapping Summary

```
Internet → Application Gateway
├─ Port 80 (HTTP)
│  ├─ /app1/* → Backend:8080 (VM1)
│  └─ /app2/* → Backend:8081 (VM2)
│
VM1 (10.0.1.10)
├─ Port 8080 (HTTP) - Web Server
├─ Port 22 (SSH) - Administration
├─ Port 443 (HTTPS) - Outbound internet
└─ Any Port - East-west to VM2
│
VM2 (10.1.1.10)
├─ Port 8081 (HTTP) - Web Server
├─ Port 22 (SSH) - Administration
├─ Port 443 (HTTPS) - Outbound internet
└─ Any Port - East-west to VM1
│
Azure Firewall (192.168.0.4)
├─ All Ports (Stateful)
└─ Outbound Public IP for internet traffic
```

## Rule Priority Order

```
FIREWALL PROCESSING ORDER:

1. DENY Rules (Explicit blocks) - HIGHEST PRIORITY
2. ALLOW Rules (Explicit allows)
3. ALLOW Network Rules (East-West)
4. ALLOW Application Rules (FQDN)
5. Implicit DENY (Default action)

Rules within same priority execute in order of collection definition.
```

## Network Interface - VM Private IP Assignment

```
VM1 Network Interface:
├─ Name: nic-vm-app1-prod
├─ Subnet: 10.0.1.0/24
├─ Private IP: 10.0.1.10 (Static)
├─ NSG: nsg-app1-prod
└─ Tags: Application=App1, Port=8080

VM2 Network Interface:
├─ Name: nic-vm-app2-prod
├─ Subnet: 10.1.1.0/24
├─ Private IP: 10.1.1.10 (Static)
├─ NSG: nsg-app2-prod
└─ Tags: Application=App2, Port=8081
```

---

# Pre-Deployment Checklist

## Azure Subscription & Access
- [ ] Azure subscription is active
- [ ] You have Owner or Contributor role
- [ ] Azure CLI installed: `az --version`
- [ ] Logged in: `az account show`
- [ ] Correct subscription selected

## Terraform & Tools
- [ ] Terraform v1.0+ installed: `terraform version`
- [ ] Git installed (for version control)
- [ ] Text editor ready (VS Code, Sublime, etc.)
- [ ] Terminal/PowerShell access

## Configuration Files
- [ ] main.tf copied and reviewed
- [ ] vms.tf copied and reviewed
- [ ] variables.tf reviewed for your needs
- [ ] terraform.tfvars created with:
  - [ ] Subscription ID filled in
  - [ ] VM password set (min 12 chars, special chars)
  - [ ] Region set correctly
  - [ ] Environment name chosen

## Security Checklist
- [ ] Strong VM password created
- [ ] SSH keys generated (if using Linux)
- [ ] terraform.tfvars NOT committed to git
- [ ] .gitignore configured: `echo "terraform.tfvars" >> .gitignore`
- [ ] Firewall rules reviewed and approved

## Resource Quotas
- [ ] Check subscription limits:
  ```bash
  az vm list-usage --location eastus
  ```
- [ ] At least 4 CPU cores available
- [ ] At least 8 GB memory available
- [ ] Public IP quota available (need 2+)

---

# Post-Deployment Validation Checklist

## Infrastructure Components
- [ ] Resource Group created
- [ ] Virtual WAN deployed
- [ ] Virtual Hub created
- [ ] Azure Firewall running (check Health status)
- [ ] Application Gateway in Running state
- [ ] 2 VNETs created and connected
- [ ] 2 VMs provisioned and started
- [ ] 2 NSGs created and applied
- [ ] 2 Route Tables created and associated

## Connectivity Tests

### Inbound (Internet → Apps)
```bash
# Get App Gateway Public IP from outputs
APPGW_IP=$(terraform output -raw app_gateway_public_ip)

# Test App1
curl http://${APPGW_IP}/app1/
# Expected: HTML with "App1 Running on Port 8080"

# Test App2
curl http://${APPGW_IP}/app2/
# Expected: HTML with "App2 Running on Port 8081"
```
- [ ] App1 accessible on /app1/*
- [ ] App2 accessible on /app2/*
- [ ] Both return 200 OK status

### East-West (VM ↔ VM)
```bash
# SSH to VM1
ssh azureuser@<VM1_IP>

# From VM1, test VM2
ping 10.1.1.10  # Should succeed
curl http://10.1.1.10:8081  # Should return App2 response
```
- [ ] VM1 can ping VM2 (10.1.1.10)
- [ ] VM1 can HTTP connect to VM2:8081
- [ ] VM2 can ping VM1 (10.0.1.10)
- [ ] VM2 can HTTP connect to VM1:8080

### Outbound (VMs → Internet)
```bash
# SSH to VM1
ssh azureuser@<VM1_IP>

# Test DNS
nslookup google.com  # Should resolve
# Test HTTPS
curl -I https://google.com  # Should return 200 OK
curl -I https://microsoft.com  # Should return 200 OK
curl -I https://example.com  # Should TIMEOUT (not allowed)
```
- [ ] DNS resolution works (port 53)
- [ ] HTTPS to google.com succeeds (port 443)
- [ ] HTTPS to microsoft.com succeeds (port 443)
- [ ] HTTPS to example.com blocked
- [ ] No public IPs visible on VMs (all traffic through Firewall)

### Firewall Verification
```bash
# In Azure Portal:
# Firewall → Logs → Firewall Logs

# Should see entries for:
# - Traffic from 10.0.1.0/24 and 10.1.1.0/24
# - Blocked: example.com, facebook.com, etc.
# - Allowed: google.com, microsoft.com
```
- [ ] Firewall Logs show east-west traffic
- [ ] Firewall Logs show outbound HTTPS traffic
- [ ] Firewall Logs show blocked non-whitelisted domains
- [ ] Firewall CPU/Memory utilization healthy

---

# Performance Metrics to Monitor

## Application Gateway Metrics
```
Portal → Application Gateway → Metrics

Watch:
├─ Request Count (should increase with traffic)
├─ Backend Response Time (should be <500ms)
├─ HTTP 5xx Errors (should be 0 or near 0)
├─ Unhealthy Host Count (should be 0)
└─ Throughput (bytes/second)
```

## Firewall Metrics
```
Portal → Firewall → Metrics

Watch:
├─ Processed Bytes (data flowing through)
├─ Firewall Health State (should be 100%)
├─ CPU Utilization
└─ Memory Utilization
```

## VM Metrics
```
Portal → Virtual Machine → Metrics

Watch:
├─ CPU %
├─ Network In Bytes
├─ Network Out Bytes
├─ OS Disk % Used
└─ Data Disk % Used
```

---

# Troubleshooting Decision Tree

```
┌─ Users cannot access /app1/
│  ├─ Check: App Gateway public IP is accessible
│  │  └─ No IP? Check Public IP resource status
│  ├─ Check: App Gateway is in Running state
│  │  └─ Failed? Check Prerequisites tab for errors
│  ├─ Check: Backend pool health
│  │  ├─ Portal → App Gateway → Backend Health
│  │  └─ Unhealthy? Check VM NSG allows port 8080 from AppGW subnet
│  ├─ Check: HTTP Settings point to correct port (8080)
│  └─ Check: URL Path Map routes /app1/* to backend-app1
│
├─ VM1 cannot reach VM2
│  ├─ Check: Route table rt-app1 exists and has route to 10.1.0.0/16
│  ├─ Check: Next hop is Virtual Appliance (Firewall)
│  ├─ Check: NSG on subnet-app1 allows to VirtualNetwork
│  ├─ Check: Firewall Policy has allow-east-west rule
│  ├─ Check: Firewall is running (check Health state)
│  └─ Check: NSG on subnet-app2 allows inbound from VirtualNetwork
│
├─ VM cannot reach Google/Microsoft
│  ├─ Check: Route table has default route (0.0.0.0/0) to Firewall
│  ├─ Check: Firewall Policy has allow-outbound-dns rule (UDP 53)
│  ├─ Check: Firewall Policy has allow-google-microsoft rule (HTTPS 443)
│  ├─ Check: NSG allows outbound 443 to Any
│  ├─ Check: Firewall public IP is assigned and healthy
│  └─ Check: Firewall Logs show traffic (Portal → Firewall → Logs)
│
└─ Traffic blocked but should be allowed
   ├─ Check: Firewall rule priority (lower = higher priority)
   ├─ Check: DENY rules don't match this traffic
   ├─ Check: ALLOW rule collection enabled
   ├─ Check: Source IP matches rule source
   ├─ Check: Destination matches rule destination
   └─ Check: Protocol/Port matches rule
```

---

# Common Errors & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `Error: Authorization failed` | Missing Azure permissions | Ask subscription owner for Contributor role |
| `Error: Quota exceeded (VMs)` | Not enough quota | Request quota increase in Portal or use smaller VM size |
| `Error: Virtual Hub creation failed` | Virtual WAN not Standard type | Delete and recreate Virtual WAN with Type=Standard |
| `Error: Cannot create route to FW IP` | Firewall IP not known | Wait for Firewall to be deployed first, then add routes |
| `Error: AppGW unhealthy backend` | VM not responding on expected port | SSH to VM, verify web server running on correct port |
| `Error: E2E route fails` | Firewall blocking traffic | Check Firewall Logs and add corresponding ALLOW rule |
| `Error: DNS resolution fails` | DNS rule missing | Add allow-outbound-dns rule (UDP 53) to Firewall |
| `Terraform destroy hangs` | NSG association not removed | Manually remove NSG associations before destroy |
| `VM has no internet` | Default route not to Firewall | Verify Route Table has 0.0.0.0/0 → Firewall |
| `Firewall public IP wasted` | No traffic flowing | Check that routes point to Firewall, NSGs allow traffic |

---

# Advanced Troubleshooting Commands

```bash
# Check Route Table effective routes on NIC
az network nic show-effective-route-table \
  --resource-group rg-vwan-prod \
  --name nic-vm-app1-prod

# Check NSG effective rules on NIC
az network nic list-effective-nsg \
  --resource-group rg-vwan-prod \
  --name nic-vm-app1-prod

# Get Firewall public IP
az network public-ip show \
  --resource-group rg-vwan-prod \
  --name pip-firewall-prod \
  --query ipAddress

# Get App Gateway backend health
az network application-gateway show-backend-health \
  --resource-group rg-vwan-prod \
  --name appgw-vwan-prod

# Query Firewall logs
az monitor log-analytics query \
  --workspace <WORKSPACE_ID> \
  --analytics-query "AzureDiagnostics | where ResourceType=='AZFW'"

# Check VNET connectivity status
az network virtual-hub connection show \
  --resource-group rg-vwan-prod \
  --vhub-name vwan-hub-eastus \
  --name conn-app1-to-hub
```

---

# Documentation Links

- [Virtual WAN Architecture](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about)
- [Firewall Policy Rules](https://learn.microsoft.com/en-us/azure/firewall/policy-rule-sets)
- [Application Gateway Routing](https://learn.microsoft.com/en-us/azure/application-gateway/url-route-overview)
- [Route Tables](https://learn.microsoft.com/en-us/azure/virtual-network/manage-route-table)
- [NSG Security Rules](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
