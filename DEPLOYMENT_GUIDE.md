# Azure Virtual WAN with Firewall and Application Gateway - Complete Deployment Guide

## Architecture Overview

```
                         INTERNET (Users)
                         ↓
                    +----+----+
                    │ Public  │ (User Access)
                    │ IP: 80  │
                    └────┬────┘
                         ↓
                  ┌──────────────────┐
                  │ Application      │
                  │ Gateway          │
                  │ (Load Balancer)  │
                  └────┬────┬────────┘
                       ↓    ↓
                 (8080)   (8081)
                       ↓    ↓
                  ┌────────────────┐
                  │  VWAN Hub      │
                  │  ┌──────────┐  │
                  │  │Firewall  │  │
                  │  │Policy    │  │
                  │  └──────────┘  │
                  └────────┬───────┘
                    ╱      ╲
           ┌─────────────┐ ┌──────────────┐
           │ VNET 1      │ │ VNET 2       │
           │ 10.0.0.0/16 │ │ 10.1.0.0/16  │
           │  ┌────────┐ │ │ ┌─────────┐  │
           │  │ VM App1│ │ │ │VM App2  │  │
           │  │ :8080  │ │ │ │ :8081   │  │
           │  └────────┘ │ │ └─────────┘  │
           └──┬──────────┘ └──────┬───────┘
              ↓                   ↓
         OUTBOUND:            OUTBOUND:
         Google.com          Microsoft.com
         Microsoft.com       Google.com
```

## Key Components & Their Roles

### 1. **Virtual WAN (vWAN)**
- Simplified branch connectivity hub
- Enables mesh networking between VNETs
- Manages hub-and-spoke topology

### 2. **Virtual Hub**
- Central connectivity point
- Hosts Firewall and integrates with App Gateway
- Address space: `192.168.0.0/23`

### 3. **Azure Firewall**
- Stateful firewall for egress/ingress filtering
- Enforces policies on east-west traffic
- Controls outbound internet access
- Location: Inside VWAN Hub (not in a separate VNET)

### 4. **Application Gateway**
- Layer 7 (Application) load balancer
- Handles inbound traffic on port 80
- Routing: Path-based (`/app1/*` → port 8080, `/app2/*` → port 8081)
- Public IP for internet access

### 5. **VNETs & Subnets**
- **VNET 1**: `10.0.0.0/16` (App1)
  - App Subnet: `10.0.1.0/24`
  - Gateway Subnet: `10.0.0.0/27`
- **VNET 2**: `10.1.0.0/16` (App2)
  - App Subnet: `10.1.1.0/24`
  - Gateway Subnet: `10.1.0.0/27`

### 6. **VMs**
- **VM1**: Hosts App1 on port 8080 (10.0.1.10)
- **VM2**: Hosts App2 on port 8081 (10.1.1.10)

---

## Traffic Flow & Routing Logic

### **Inbound Traffic (User → App)**

```
User (Internet) 
  ↓ (Port 80)
Application Gateway (Public IP)
  ├─ URL Path: /app1/* → Backend Pool: VM1 (10.0.1.10:8080)
  └─ URL Path: /app2/* → Backend Pool: VM2 (10.1.1.10:8081)
```

**Example Requests:**
```
http://AppGW-PublicIP/app1/index → Routed to VM1:8080
http://AppGW-PublicIP/app2/status → Routed to VM2:8081
```

### **East-West Traffic (VM ↔ VM)**

```
VM1 (10.0.1.10) sends traffic to 10.1.0.0/16 (VNET 2)
  ↓
Route Table (RT1) checks destination
  → Route: 10.1.0.0/16 → Next Hop: Firewall (192.168.0.4)
  ↓
Azure Firewall receives traffic
  → Firewall Policy: Allow VNET-to-VNET traffic
  ↓
VM2 (10.1.1.10) receives traffic
```

**Firewall Rule Applied:**
```
Source: 10.0.0.0/16, 10.1.0.0/16
Destination: 10.0.0.0/16, 10.1.0.0/16
Action: ALLOW
Protocols: TCP, UDP
```

### **Outbound Internet Traffic (VM → Internet)**

```
VM1 (10.0.1.10) requests google.com:443
  ↓
Route Table (RT1) checks destination (0.0.0.0/0)
  → Route: 0.0.0.0/0 → Next Hop: Firewall (192.168.0.4)
  ↓
Azure Firewall receives traffic
  → Firewall Policy: Allow google.com, microsoft.com (FQDN Rule)
  ↓
Firewall SNAT/PAT translates source to Firewall Public IP
  ↓
Internet response returns to Firewall
  ↓
Firewall returns traffic to VM1
```

**Firewall Rule Applied:**
```
Source: 10.0.0.0/16, 10.1.0.0/16
Destination: google.com, microsoft.com
Protocol: HTTPS (Port 443)
Action: ALLOW
```

---

## Route Tables Explained

### **Route Table for VNET 1 (rt-app1)**

| Destination | Next Hop Type | Next Hop IP | Purpose |
|------------|---------------|------------|---------|
| `10.1.0.0/16` | Virtual Appliance | `192.168.0.4` (FW) | Route VNET2 traffic through Firewall |
| `0.0.0.0/0` | Virtual Appliance | `192.168.0.4` (FW) | Default route: All internet traffic via Firewall |

### **Route Table for VNET 2 (rt-app2)**

| Destination | Next Hop Type | Next Hop IP | Purpose |
|------------|---------------|------------|---------|
| `10.0.0.0/16` | Virtual Appliance | `192.168.0.4` (FW) | Route VNET1 traffic through Firewall |
| `0.0.0.0/0` | Virtual Appliance | `192.168.0.4` (FW) | Default route: All internet traffic via Firewall |

---

## Firewall Policy Rules

### **Application Rules (FQDN Filtering)**

```
Rule: "allow-google-microsoft"
Source IPs: 10.0.0.0/16, 10.1.0.0/16
Destination FQDNs: google.com, *.microsoft.com, *.googleapis.com
Protocol: HTTPS (Port 443)
Action: ALLOW
```

### **Network Rules (East-West + DNS)**

```
Rule 1: "allow-east-west"
Source: 10.0.0.0/16, 10.1.0.0/16
Destination: 10.0.0.0/16, 10.1.0.0/16
Protocols: TCP, UDP
Ports: All (*)
Action: ALLOW

Rule 2: "allow-outbound-dns"
Source: 10.0.0.0/16, 10.1.0.0/16
Destination: Any
Protocol: UDP Port 53
Action: ALLOW (Required for DNS resolution)
```

---

## NSG (Network Security Group) Rules

### **NSG for VNET 1 (nsg-app1)**

```
Inbound Rules:
1. Allow Port 8080 from App Gateway Subnet (192.168.0.0/26)
   - Allows App Gateway to reach VM1 on port 8080
   
2. Allow All from VirtualNetwork
   - Enables east-west communication with VNET 2

Outbound Rules:
1. Allow Port 443 (HTTPS) to Internet
   - Required for connecting to Google/Microsoft sites
   
2. Implicit: Allow 10.0.0.0/8 (VirtualNetwork)
```

### **NSG for VNET 2 (nsg-app2)**

```
Inbound Rules:
1. Allow Port 8081 from App Gateway Subnet (192.168.0.0/26)
   - Allows App Gateway to reach VM2 on port 8081
   
2. Allow All from VirtualNetwork
   - Enables east-west communication with VNET 1

Outbound Rules:
1. Allow Port 443 (HTTPS) to Internet
   - Required for connecting to Google/Microsoft sites
```

---

## Deployment Steps - Terraform

### **Prerequisites**
- Azure CLI installed and authenticated
- Terraform v1.0+
- Appropriate IAM permissions (Subscription Owner/Contributor)

### **Step 1: Setup Terraform Files**

```bash
# Create a new directory
mkdir azure-vwan-terraform
cd azure-vwan-terraform

# Copy the provided Terraform files
# Files needed:
# - main.tf
# - vms.tf
# - variables.tf
# - terraform.tfvars (update with your values)
```

### **Step 2: Configure terraform.tfvars**

```bash
# Copy example file and edit
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Required values:**
```
subscription_id = "your-subscription-id-here"
vm_password     = "ComplexPassword123!@#"  # Min 12 chars with special chars
```

### **Step 3: Initialize Terraform**

```bash
terraform init
```

This command:
- Downloads Terraform Azure provider
- Sets up local backend for state management
- Validates provider configuration

### **Step 4: Validate Configuration**

```bash
terraform fmt -recursive        # Format code
terraform validate             # Check syntax
terraform plan -out=tfplan    # Preview changes
```

Review the plan output to ensure all resources are as expected.

### **Step 5: Deploy Infrastructure**

```bash
terraform apply tfplan
```

**Expected deployment time:** 15-30 minutes

Resources deployed in order:
1. Resource Group
2. Virtual WAN & Hub
3. VNETs & Subnets
4. NSGs & Rules
5. Route Tables
6. Network Interfaces
7. Firewall & Policies
8. Application Gateway
9. VMs & Extensions

### **Step 6: Verify Deployment**

```bash
# Get outputs
terraform output

# Outputs will show:
# - App Gateway Public IP
# - Firewall Public IP
# - VM Private IPs
```

---

## Manual Azure Portal Deployment Steps

### **Phase 1: Create Virtual WAN Infrastructure**

#### **Step 1.1: Create Resource Group**
1. Azure Portal → **Resource Groups** → **Create**
2. Name: `rg-vwan-prod`
3. Region: `East US`
4. Click **Create**

#### **Step 1.2: Create Virtual WAN**
1. Search for **Virtual WANs**
2. Click **Create**
3. Configuration:
   - Resource Group: `rg-vwan-prod`
   - Name: `vwan-prod`
   - Region: `East US`
   - Type: **Standard** (Important: Required for Firewall)
4. Click **Create**

#### **Step 1.3: Create Virtual Hub**
1. Go to created Virtual WAN
2. Click **Hubs** → **+ New Hub**
3. Configuration:
   ```
   Hub Name: vwan-hub-eastus
   Hub Address Space: 192.168.0.0/23
   Region: East US
   ```
4. Click **Create**

---

### **Phase 2: Deploy Virtual Networks**

#### **Step 2.1: Create VNET 1**
1. **Virtual Networks** → **Create**
2. Basics Tab:
   - Name: `vnet-app1-prod`
   - Region: `East US`
   - IPv4 Address Space: `10.0.0.0/16`
3. IP Addresses Tab:
   - Add Subnet:
     - Name: `subnet-app1`
     - Address Range: `10.0.1.0/24`
   - Add Subnet:
     - Name: `GatewaySubnet`
     - Address Range: `10.0.0.0/27`
4. Click **Create**

#### **Step 2.2: Create VNET 2**
Repeat Step 2.1 with:
- Name: `vnet-app2-prod`
- IPv4 Space: `10.1.0.0/16`
- Subnets:
  - `subnet-app2`: `10.1.1.0/24`
  - `GatewaySubnet`: `10.1.0.0/27`

#### **Step 2.3: Connect VNETs to VWAN Hub**
1. Go to Virtual Hub (`vwan-hub-eastus`)
2. Click **Hub Virtual Network Connections** → **Add Hub Connection**
3. For VNET 1:
   - Name: `conn-app1-to-hub`
   - Virtual Network: `vnet-app1-prod`
   - Route Propagation: **Enabled**
4. Click **Create**
5. Repeat for VNET 2

---

### **Phase 3: Deploy Azure Firewall**

#### **Step 3.1: Create Firewall**
1. Go to Virtual Hub → **Azure Firewall**
2. Click **Deploy Azure Firewall** or **Create new**
3. Configuration:
   ```
   Firewall Name: fw-vwan-hub-prod
   Firewall SKU: Standard (or Premium for advanced features)
   Public IP: Create new (pip-firewall-prod)
   Virtual Hub: vwan-hub-eastus
   ```
4. Click **Create**

#### **Step 3.2: Create Firewall Policy**
1. **Firewall Policies** → **Create**
2. Name: `fwpol-vwan-prod`
3. Region: `East US`
4. Tier: **Standard**
5. Click **Create**

#### **Step 3.3: Add Firewall Rules**
1. Go to Firewall Policy → **Rules (Classic)**
2. Click **Application Rule Collection** → **Add**:
   ```
   Collection Name: app-rules
   Priority: 100
   Rule Action: Allow
   
   Rule 1:
   Name: allow-google-microsoft
   Source Type: IP Address
   Source: 10.0.0.0/16, 10.1.0.0/16
   Protocol: HTTPS
   Destination Type: FQDN
   Destination: google.com, *.microsoft.com, *.googleapis.com
   ```
3. Click **Network Rule Collection** → **Add**:
   ```
   Collection Name: network-rules
   Priority: 200
   Rule Action: Allow
   
   Rule 1 (East-West):
   Name: allow-east-west
   Protocol: TCP, UDP
   Source Type: IP Address
   Source: 10.0.0.0/16, 10.1.0.0/16
   Destination Type: IP Address
   Destination: 10.0.0.0/16, 10.1.0.0/16
   Destination Ports: *
   
   Rule 2 (DNS):
   Name: allow-outbound-dns
   Protocol: UDP
   Source: 10.0.0.0/16, 10.1.0.0/16
   Destination: *
   Destination Ports: 53
   ```

---

### **Phase 4: Deploy Application Gateway**

#### **Step 4.1: Create Hub VNET for App Gateway**
1. **Virtual Networks** → **Create**
2. Name: `vnet-hub-prod`
3. Address Space: `192.168.0.0/24`
4. Subnet:
   - Name: `subnet-appgw`
   - Address Range: `192.168.0.0/26`
5. Click **Create**

#### **Step 4.2: Create Public IP for App Gateway**
1. **Public IP Addresses** → **Create**
2. Name: `pip-appgw-prod`
3. SKU: **Standard**
4. Click **Create**

#### **Step 4.3: Create Application Gateway**
1. **Application Gateways** → **Create**
2. Basics:
   - Name: `appgw-vwan-prod`
   - Tier: **Standard v2**
   - Capacity: 2
3. Frontends:
   - Public IP: `pip-appgw-prod`
   - Port: 80
4. Backends:
   - Pool 1: `backend-app1` (Add later with VM IP)
   - Pool 2: `backend-app2` (Add later with VM IP)
5. HTTP Settings:
   - Setting 1: Port 8080, Protocol HTTP
   - Setting 2: Port 8081, Protocol HTTP
6. Rules:
   - Rule 1: `listener-http` → URL Path Map
7. URL Path Map:
   - `/app1/*` → backend-app1:8080
   - `/app2/*` → backend-app2:8081
8. Click **Create**

---

### **Phase 5: Deploy Network Security Groups**

#### **Step 5.1: Create NSG for App1**
1. **Network Security Groups** → **Create**
2. Name: `nsg-app1-prod`
3. Go to **Inbound Security Rules** → **Add**:
   ```
   Rule 1:
   Name: allow-app-gateway-8080
   Priority: 100
   Direction: Inbound
   Protocol: TCP
   Port Range: 8080
   Source: 192.168.0.0/26 (App Gateway Subnet)
   ```
4. Add Outbound Rule:
   ```
   Rule 2:
   Name: allow-outbound-https
   Priority: 100
   Direction: Outbound
   Protocol: TCP
   Port Range: 443
   Destination: *
   ```
5. Associate to `subnet-app1`

#### **Step 5.2: Repeat for App2**
Same as above but:
- NSG Name: `nsg-app2-prod`
- Port: 8081
- Associate to `subnet-app2`

---

### **Phase 6: Create Route Tables**

#### **Step 6.1: Create Route Table for VNET 1**
1. **Route Tables** → **Create**
2. Name: `rt-app1-prod`
3. Once created, go to **Routes** → **Add**:
   ```
   Route 1:
   Name: to-vnet2-via-fw
   Address Prefix: 10.1.0.0/16
   Next Hop Type: Virtual Appliance
   Next Hop IP: 192.168.0.4 (Firewall IP in hub)
   
   Route 2:
   Name: default-via-fw
   Address Prefix: 0.0.0.0/0
   Next Hop Type: Virtual Appliance
   Next Hop IP: 192.168.0.4
   ```
4. **Subnets** → **Associate**:
   - VNET: `vnet-app1-prod`
   - Subnet: `subnet-app1`

#### **Step 6.2: Create Route Table for VNET 2**
Repeat with:
- Route to VNET1 (10.0.0.0/16)
- Associate to `subnet-app2`

---

### **Phase 7: Deploy Virtual Machines**

#### **Step 7.1: Create VM 1**
1. **Virtual Machines** → **Create**
2. Basics:
   - Name: `vm-app1-prod`
   - Image: Ubuntu 20.04 LTS (or Windows Server 2019)
   - Size: Standard_B2s
3. Networking:
   - VNET: `vnet-app1-prod`
   - Subnet: `subnet-app1`
   - NSG: `nsg-app1-prod`
   - Public IP: **None** (Traffic via App Gateway)
4. Advanced (User Data):
   ```bash
   #!/bin/bash
   apt-get update
   apt-get install -y nginx
   echo "<h1>App1 Running on Port 8080</h1>" > /var/www/html/index.html
   # Configure to listen on 8080
   sed -i 's/listen 80/listen 8080/' /etc/nginx/sites-enabled/default
   systemctl restart nginx
   ```
5. Click **Create**

#### **Step 7.2: Create VM 2**
Repeat with:
- Name: `vm-app2-prod`
- VNET: `vnet-app2-prod`
- Subnet: `subnet-app2`
- NSG: `nsg-app2-prod`
- Port: 8081

---

### **Phase 8: Update Application Gateway Backend Pools**

1. Go to Application Gateway → **Backend Pools**
2. Edit `backend-app1`:
   - Add Target: IP address `10.0.1.10` (VM1 private IP)
3. Edit `backend-app2`:
   - Add Target: IP address `10.1.1.10` (VM2 private IP)

---

## Testing & Validation

### **Test 1: Inbound Connectivity**

```bash
# Get App Gateway Public IP
curl http://<AppGW-PublicIP>/app1/
# Expected: "App1 Running on Port 8080"

curl http://<AppGW-PublicIP>/app2/
# Expected: "App2 Running on Port 8081"
```

### **Test 2: East-West Connectivity**

```bash
# SSH into VM1
ssh azureuser@<VM1-PublicIP>

# From VM1, ping VM2
ping 10.1.1.10
# Expected: Ping successful

# Test HTTP connectivity to VM2:8081
curl http://10.1.1.10:8081
# Expected: "App2 Running on Port 8081"
```

### **Test 3: Outbound Internet Connectivity**

```bash
# SSH into VM1
ssh azureuser@<VM1-PublicIP>

# Test DNS resolution
nslookup google.com
# Expected: Resolves successfully

# Test HTTPS connectivity (through Firewall)
curl -I https://google.com
# Expected: HTTP/2 200 OK or similar

curl -I https://microsoft.com
# Expected: HTTP/2 200 OK or similar
```

### **Test 4: Firewall Blocking (Negative Test)**

```bash
# SSH into VM1
ssh azureuser@<VM1-PublicIP>

# Try to access non-whitelisted domain
curl -I https://example.com
# Expected: Timeout or connection refused
```

---

## Troubleshooting

### **Issue: VMs cannot reach App Gateway**

**Cause:** NSG or route table misconfiguration

**Solution:**
1. Check NSG inbound rules allow port 8080/8081 from App Gateway subnet
2. Verify Application Gateway is in Running state
3. Check Backend Health in App Gateway settings

### **Issue: East-West traffic blocked**

**Cause:** Firewall policy denying traffic

**Solution:**
1. Review Firewall Logs: Portal → Firewall → Logs
2. Ensure Network Rule "allow-east-west" is enabled
3. Verify Route Table next hops point to Firewall

### **Issue: Outbound internet fails**

**Cause:** DNS or Firewall FQDN rule misconfiguration

**Solution:**
1. Verify DNS rule (UDP 53) is allowed
2. Check FQDN rules in Firewall Policy
3. Test with telnet to verify port connectivity
4. Check Firewall public IP is properly assigned

---

## Cost Estimation (Monthly)

| Component | SKU | Estimated Cost |
|-----------|-----|------------------|
| Virtual WAN | Standard | $0.25/hour |
| Virtual Hub | - | $0.25/hour |
| Azure Firewall | Standard | $1.25/hour |
| Application Gateway | v2 | $0.20/hour + $0.006/capacity |
| VMs (2x) | Standard_B2s | $0.05/hour each |
| Public IPs (2) | Standard | $0.005/hour each |
| **Total Estimated** | - | **~$150-200/month** |

---

## Cleanup

### **Terraform Cleanup**
```bash
terraform destroy -auto-approve
```

### **Manual Cleanup (Azure Portal)**
1. Delete all VMs
2. Delete Virtual Hub (this removes Firewall)
3. Delete Virtual WAN
4. Delete VNETs
5. Delete Resource Group

---

## Advanced Configurations

### **Enable Firewall Diagnostics**
```
Portal → Firewall → Diagnostic Settings → Add diagnostic setting
Enable: Firewall Logs, Application Rule Logs, Network Rule Logs
Destination: Log Analytics Workspace
```

### **Add Custom Routes**
```
Route Tables → Edit Routes
Add routes for specific subnets or on-premises networks
```

### **Enable DDoS Protection**
```
Portal → DDoS Protection Plans → Create
Associate with App Gateway Public IP
```

### **SSL/TLS Termination in App Gateway**
```
Application Gateway → HTTPS Listeners
Upload SSL certificate
Configure HTTPS port 443
```

---

## Support & Documentation

- **Azure Virtual WAN**: https://learn.microsoft.com/en-us/azure/virtual-wan/
- **Azure Firewall**: https://learn.microsoft.com/en-us/azure/firewall/
- **Application Gateway**: https://learn.microsoft.com/en-us/azure/application-gateway/
- **Terraform Azure Provider**: https://registry.terraform.io/providers/hashicorp/azurerm/latest

---

## Key Takeaways

✅ **What this architecture achieves:**
- Centralized firewall policy management
- Scalable hub-and-spoke connectivity
- Layer 7 application routing
- Complete traffic flow control
- Compliance-ready network design

✅ **Traffic patterns enabled:**
- Internet users → Apps via App Gateway
- VM-to-VM communication via Firewall
- Outbound internet through Firewall
- Controlled DNS and HTTPS access
- East-West encryption capability

✅ **Security benefits:**
- Single point of policy enforcement
- FQDN-based application rules
- Network segmentation
- Stateful firewall inspection
- NSG + Firewall defense-in-depth
