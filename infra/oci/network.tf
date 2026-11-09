# One public subnet with NO inbound rules at all. The node needs outbound internet (packages, k3s, Tailscale);
# everything inbound arrives over Tailscale, which works through outbound connections only.

resource "oci_core_vcn" "qops" {
  compartment_id = oci_identity_compartment.qops.id
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "qops-vcn"
  dns_label      = "qops"
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "qops" {
  compartment_id = oci_identity_compartment.qops.id
  vcn_id         = oci_core_vcn.qops.id
  display_name   = "qops-igw"
  enabled        = true
  freeform_tags  = local.tags
}

resource "oci_core_route_table" "public" {
  compartment_id = oci_identity_compartment.qops.id
  vcn_id         = oci_core_vcn.qops.id
  display_name   = "qops-public"
  freeform_tags  = local.tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.qops.id
  }
}

resource "oci_core_security_list" "node" {
  compartment_id = oci_identity_compartment.qops.id
  vcn_id         = oci_core_vcn.qops.id
  display_name   = "qops-node-egress-only"
  freeform_tags  = local.tags

  # Stateful egress: replies to the node's own connections come back in; nothing else can.
  egress_security_rules {
    description = "all outbound"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
  # Deliberately no ingress_security_rules (tests/plan.tftest.hcl checks this).
}

resource "oci_core_subnet" "public" {
  compartment_id    = oci_identity_compartment.qops.id
  vcn_id            = oci_core_vcn.qops.id
  cidr_block        = cidrsubnet(var.vcn_cidr, 8, 1)
  display_name      = "qops-public"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public.id
  security_list_ids = [oci_core_security_list.node.id]
  freeform_tags     = local.tags
}
