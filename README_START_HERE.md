# Azure VWAN Architecture - START HERE 🚀

## What You've Received

This package contains everything needed to build your Azure Virtual WAN architecture with:
- ✅ Centralized Firewall for traffic control
- ✅ Application Gateway for load balancing
- ✅ Two VNETs with VMs running applications on ports 8080 & 8081
- ✅ Internet user access + VM outbound access + East-West connectivity
- ✅ Complete Terraform automation
- ✅ Detailed manual deployment steps

---

## Quick Start (5 Minutes)

### Option 1: Automated Deployment with Terraform (Recommended)

```bash
# 1. Open terminal and navigate to this directory
cd <your-download-directory>

# 2. Update configuration
nano terraform.tfvars
# Edit these values:
# - subscription_id: Your Azure subscription ID
# - vm_password: Strong password for VMs

# 3. Deploy
terraform init
terraform plan
terraform apply

# Wait 15-30 minutes for deployment...
# Done! Check terraform output for IPs
```

### Option 2: Manual Deployment in Azure Portal

See **DEPLOYMENT_GUIDE.md** → **"Manual Azure Portal Deployment Steps"** section for detailed step-by-step instructions.

---

## Understanding Your Architecture

### What is each component?

| Component | Purpose | Your Setup |
|-----------|---------|-----------|
| **Virtual WAN** | Network hub | Connects 2 VNETs through single hub |
| **Azure Firewall** | Firewall | Filters east-west & outbound traffic |
| **App Gateway** | Load balancer | Routes users: `/app1/*` → VM1:8080, `/app2/*` → VM2:8081 |
| **VNET 1** | Network | Contains VM1 (10.0.1.10) running App1 |
| **VNET 2** | Network | Contains VM2 (10.1.1.10) running App2 |
| **Route Tables** | Traffic steering | Ensures all non-local traffic goes through Firewall |
| **NSGs** | Access control | Allow ports 8080/8081 + outbound HTTPS |

### How does traffic flow?

```
Internet Users
    ↓
http://AppGW-IP/app1/ → Port 8080 (VM1)
http://AppGW-IP/app2/ → Port 8081 (VM2)
    
VM1 ←→ VM2 (via Firewall)
    
VMs → Google.com / Microsoft.com (via Firewall)
```

---

## File Descriptions

### Terraform Files
- **main.tf** - Core infrastructure (VWAN, VNETs, Firewall, App Gateway, NSGs, Route Tables)
- **vms.tf** - Virtual Machine configurations with auto-setup
- **variables.tf** - All configurable parameters
- **terraform.tfvars.example** - Template for your settings

### Documentation Files
- **DEPLOYMENT_GUIDE.md** - 50+ page detailed guide with both Terraform and manual steps
- **QUICK_REFERENCE.md** - Traffic flows, troubleshooting, checklists, commands
- **README_START_HERE.md** - This file

---

## Step-by-Step Terraform Deployment

### Step 1: Prerequisites (10 minutes)

```bash
# Check Azure CLI is installed
az --version

# Check Terraform is installed
terraform version

# Login to Azure
az login

# Set correct subscription
az account set --subscription "your-subscription-id"
```

### Step 2: Prepare Configuration (5 minutes)

```bash
# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars

# REQUIRED EDITS:
# subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
# vm_password     = "YourSecurePassword123!@#"
```

**Password Requirements:**
- Minimum 12 characters
- Must contain: uppercase, lowercase, numbers, special characters
- Example: `P@ssw0rd!Azure2024`

### Step 3: Initialize Terraform (5 minutes)

```bash
terraform init
```

This downloads the Azure provider and sets up the project.

### Step 4: Review Your Deployment Plan (5 minutes)

```bash
terraform plan -out=tfplan
```

**Expected resources to create:**
- 1 Resource Group
- 1 Virtual WAN
- 1 Virtual Hub
- 2 Virtual Networks
- 4 Subnets
- 1 Azure Firewall + Policy
- 1 Application Gateway
- 2 VMs
- 2 NSGs
- 2 Route Tables
- 2 Network Interfaces
- 3 Public IPs

### Step 5: Deploy Infrastructure (20-30 minutes)

```bash
terraform apply tfplan
```

Watch the deployment progress. This will:
1. Create resource group and basic networking (2 min)
2. Deploy VWAN and Hub (5 min)
3. Deploy Firewall (10 min)
4. Deploy Application Gateway (10 min)
5. Deploy VMs and configure them (5 min)

When complete, you'll see output:
```
Outputs:

app_gateway_public_ip = "40.x.x.x"
firewall_public_ip = "40.x.x.x"
vm1_nic_private_ip = "10.0.1.10"
vm2_nic_private_ip = "10.1.1.10"
vwan_hub_id = "/subscriptions/..."
```

### Step 6: Verify Your Deployment (5 minutes)

```bash
# Test App1
curl http://40.x.x.x/app1/
# Expected: HTML with "App1 Running on Port 8080"

# Test App2
curl http://40.x.x.x/app2/
# Expected: HTML with "App2 Running on Port 8081"

# Store for later
APPGW_IP="40.x.x.x"
```

---

## Manual Deployment Quick Reference

If you prefer Azure Portal instead of Terraform:

### In Order:
1. **Resource Group** - Create new: `rg-vwan-prod`
2. **Virtual WAN** - Type: Standard (important!)
3. **Virtual Hub** - Address space: 192.168.0.0/23
4. **VNETs** - Two networks: 10.0.0.0/16 and 10.1.0.0/16
5. **Hub Connections** - Connect VNETs to VWAN Hub
6. **Azure Firewall** - Deploy in the Hub
7. **Firewall Policy** - Add rules (see DEPLOYMENT_GUIDE.md)
8. **App Gateway** - For public access
9. **NSGs** - Security rules for each subnet
10. **Route Tables** - Steer traffic through Firewall
11. **VMs** - Two Windows/Linux servers
12. **Configure App Gateway** - Add backend pools with VM IPs

**Estimated time: 45-60 minutes manually**

→ Full steps in: **DEPLOYMENT_GUIDE.md** → Search "Manual Azure Portal"

---

## Testing Your Setup

### Test 1: Public Access

```bash
# Get App Gateway IP from terraform output
APPGW_IP=$(terraform output -raw app_gateway_public_ip)

# Access App1 (port 8080)
curl http://${APPGW_IP}/app1/
# Should see: "App1 Running on Port 8080"

# Access App2 (port 8081)
curl http://${APPGW_IP}/app2/
# Should see: "App2 Running on Port 8081"
```

### Test 2: East-West Connectivity

```bash
# SSH to VM1 (You'll need to RDP for Windows VMs)
# Note: VMs have no public IPs, so use VPN/Bastion for access
# See DEPLOYMENT_GUIDE.md for VM access details

# From VM1, test reaching VM2
ping 10.1.1.10
# Expected: Ping succeeds

curl http://10.1.1.10:8081
# Expected: "App2 Running on Port 8081"
```

### Test 3: Outbound Internet Access

```bash
# From VM1, test internet connectivity
nslookup google.com
# Expected: Resolves successfully

curl https://google.com
# Expected: Response from google

curl https://microsoft.com
# Expected: Response from microsoft

curl https://example.com
# Expected: Timeout (blocked by firewall)
```

✅ **If all tests pass, you have a fully functional architecture!**

---

## Common Issues & Quick Fixes

### Issue: "Resource Group already exists"
**Fix:** Either delete the old one or change `resource_group_name` in main.tf

### Issue: "Quota exceeded"
**Fix:** Request quota increase in Azure Portal (Subscriptions → Usage + quotas)

### Issue: App Gateway shows "Unhealthy" backends
**Fix:** 
1. Check NSG allows port 8080/8081 from App Gateway subnet
2. Verify VMs are running and web servers are up
3. Check VM startup scripts completed

### Issue: East-West traffic doesn't work
**Fix:**
1. Verify Route Table exists with routes to other VNET via Firewall
2. Check NSG allows VirtualNetwork in inbound
3. Verify Firewall policy has "allow-east-west" rule

### Issue: Outbound internet fails
**Fix:**
1. Check Firewall policy has DNS rule (UDP 53)
2. Check Firewall policy has FQDN rule for google.com/microsoft.com
3. Verify NSG allows outbound port 443
4. Check Firewall is in Running state

→ Complete troubleshooting in: **QUICK_REFERENCE.md** → Troubleshooting section

---

## Detailed Documentation

### For Routing & Traffic Flow Details
→ Read: **QUICK_REFERENCE.md**
- Network addresses
- Traffic flows (4 scenarios)
- Port mappings
- Rule priority
- Visual diagrams

### For Complete Deployment Steps
→ Read: **DEPLOYMENT_GUIDE.md**
- Architecture overview
- Component descriptions
- All Azure Portal steps
- All Terraform configuration
- Firewall rules explained
- Route table setup
- NSG rules
- VM deployment
- Testing & validation
- Troubleshooting
- Cost estimation
- Cleanup

### For Quick Validation Checklists
→ Read: **QUICK_REFERENCE.md**
- Pre-deployment checklist
- Post-deployment checklist
- Validation commands
- Metrics to monitor
- Decision trees
- Common errors table

---

## Next Steps

### After Deployment:

1. **Connect to VMs** (via Bastion or VPN)
   - SSH/RDP to VMs
   - Verify applications are running
   - Check application logs

2. **Configure Custom Applications**
   - Modify startup scripts in vms.tf
   - Deploy your actual applications
   - Update health probe endpoints if needed

3. **Enable SSL/TLS**
   - Upload SSL certificate to App Gateway
   - Switch listeners to HTTPS
   - Redirect HTTP to HTTPS

4. **Monitor & Alert**
   - Set up Log Analytics workspace
   - Enable diagnostic settings on Firewall/App Gateway
   - Create action groups for alerts

5. **Optimize Costs**
   - Review metrics for rightsizing
   - Consider Reserved Instances for VMs
   - Adjust capacity based on usage

6. **Add More Environments**
   - Duplicate VNETs for staging/dev
   - Connect to same VWAN Hub
   - Reuse Firewall policies

---

## Cost Estimation

**Monthly costs (US East):**
- Virtual WAN: $0.25/hr = ~$180/month
- Virtual Hub: $0.25/hr = ~$180/month
- Firewall (Standard): $1.25/hr = ~$900/month
- App Gateway v2: ~$300/month
- 2x VM (B2s): ~$75/month
- Public IPs: ~$5/month
- **Total: ~$1,600-1,800/month**

*Costs vary by region. Use Azure Pricing Calculator for accurate estimates.*

---

## Support Resources

- **Azure Documentation**: https://learn.microsoft.com/azure/
- **Virtual WAN**: https://learn.microsoft.com/en-us/azure/virtual-wan/
- **Firewall**: https://learn.microsoft.com/en-us/azure/firewall/
- **App Gateway**: https://learn.microsoft.com/en-us/azure/application-gateway/
- **Terraform Azure**: https://registry.terraform.io/providers/hashicorp/azurerm/

---

## What's In Your Architecture?

✅ **Inbound Flow**
- Users access applications on public IP
- Application Gateway routes to different VMs based on URL
- Load balancing across backend pools
- Health monitoring of backend VMs

✅ **East-West Flow**
- VM-to-VM communication through Firewall
- Stateful inspection of internal traffic
- Network-level segmentation
- Audit trail of inter-VNET communication

✅ **Outbound Flow**
- VMs connect to internet through Firewall
- FQDN-based filtering (whitelisting)
- DNS resolution through Firewall
- SNAT for source IP translation
- Logging of all outbound connections

✅ **Security**
- Two-layer filtering (NSG + Firewall)
- Centralized policy management
- No public IPs on VMs
- Audit logs for compliance
- DDoS protection ready

---

## Emergency Cleanup

If you need to remove everything:

```bash
# Terraform cleanup (safest method)
terraform destroy -auto-approve

# Manual cleanup if Terraform fails
az group delete --name rg-vwan-prod --yes
```

⚠️ **WARNING:** This will delete ALL resources. Be sure before running!

---

## Questions?

Before asking:
1. Check **QUICK_REFERENCE.md** Troubleshooting section
2. Review **DEPLOYMENT_GUIDE.md** for your specific step
3. Check Azure portal for resource status
4. Look at deployment logs: `terraform show`

---

**You're ready to deploy! Choose Terraform or Azure Portal above and follow the steps. Total time: 20-60 minutes. Good luck! 🎉**

---

## File Checklist

Before you start, make sure you have:
- [ ] main.tf
- [ ] vms.tf
- [ ] variables.tf
- [ ] terraform.tfvars.example (rename to terraform.tfvars)
- [ ] DEPLOYMENT_GUIDE.md
- [ ] QUICK_REFERENCE.md
- [ ] README_START_HERE.md (this file)

All files should be in the same directory.

---

**Happy deploying! 🚀**
