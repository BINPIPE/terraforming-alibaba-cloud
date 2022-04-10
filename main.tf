terraform { # Terraform related configs
  backend "local" { # We use local backend to keep it simple
    path = "terraform.tfstate" # The file where the Terraform states stores in
  }
}

provider "alicloud" {
  # Here you can find the "Region ID": https://www.alibabacloud.com/help/doc-detail/40654.htm
  region     = "cn-beijing"

  # How to create a pair of access_key and secret_key: https://www.alibabacloud.com/help/doc-detail/53045.htm
  access_key = "..."
  secret_key = "..."
}

# Some useful variables to reduce copy-paste, you can add whatever you like
locals {
  prefix   = "foo"
  domain   = "wi1dcard.dev"
  hostname = "${local.prefix}.${local.domain}"
  zone     = "cn-beijing-h"
}

resource "alicloud_vpc" "default" {
  # Here we used the variables in the `locals` section above
  name       = local.prefix
  # Set the CIDR for this VPC
  cidr_block = "192.168.200.0/24"
}

resource "alicloud_vswitch" "default" {
  # Use the VPC's ID
  vpc_id            = alicloud_vpc.default.id
  # Set the CIDR for this switch, must be in the CIDR of the VPC
  cidr_block        = "192.168.200.0/24"
  # As the VPC is a region-specified resource, switches are for zones
  availability_zone = local.zone
}

resource "alicloud_security_group" "default" {
  name                = local.prefix
  vpc_id              = alicloud_vpc.default.id
  # Allow instances in the same security group reaching each other
  inner_access_policy = "Accept"
}

resource "alicloud_security_group_rule" "allow_ssh" {
  # Refer the security group ID
  security_group_id = alicloud_security_group.default.id
  type              = "ingress"
  ip_protocol       = "tcp"
  # Since the security group is for using in the VPC, you need to set it to intranet: https://www.terraform.io/docs/providers/alicloud/r/security_group_rule.html
  nic_type          = "intranet"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  port_range        = "22/22"
}

resource "alicloud_security_group_rule" "allow_icmp" {
  security_group_id = alicloud_security_group.default.id
  type              = "ingress"
  ip_protocol       = "icmp"
  nic_type          = "intranet"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
}


resource "alicloud_key_pair" "default" {
  key_name   = local.prefix
  public_key = "ssh-rsa ... wi1dcard@wi1dcard.dev"
}

resource "alicloud_instance" "default" {
  # You can enable `dry_run` and run `terraform apply` to call the Alibaba Cloud API but not really create an instance
  dry_run = false

  instance_name   = local.hostname # Refer to local variables
  host_name       = local.hostname
  key_name        = alicloud_key_pair.default.key_name # Refer to the key pair name
  vswitch_id      = alicloud_vswitch.default.id # Refer to the vswitch ID
  security_groups = [alicloud_security_group.default.id] # The security groups associated to the instance

  # Check out the whole list of the instance types: https://www.alibabacloud.com/help/doc-detail/25378.htm
  # We use the cheapest instance type (I found so far) for testing
  instance_type        = "ecs.s6-c1m1.small"
  instance_charge_type = "PostPaid" # Of course post paid!
  credit_specification = "Standard"
  spot_strategy        = "NoSpot"

  # You can find the image IDs on https://ecs.console.aliyun.com/ > Instances & Images > Images > Public Image
  image_id                      = "ubuntu_18_04_x64_20G_alibase_20191225.vhd"
  system_disk_category          = "cloud_efficiency"
  system_disk_size              = 20
  # Disable the useless "security enhancement" features
  security_enhancement_strategy = "Deactive"

  internet_max_bandwidth_in  = 100
  internet_max_bandwidth_out = 100
  internet_charge_type       = "PayByTraffic" # Of course pay by traffic!!
}

resource "alicloud_dns_record" "default" {
  name        = local.domain
  host_record = local.prefix
  type        = "A"
  ttl         = 600
  routing     = "default"

  # Refer to the public IP of the instance
  value = alicloud_instance.default.public_ip
}

output "public_ip" {
  value = alicloud_instance.default.public_ip
}
