output "node_name" {
  description = "Hostname of the node in OCI and on the tailnet."
  value       = var.node_name
}

output "node_tailnet_fqdn" {
  description = "MagicDNS name of the node."
  value       = "${var.node_name}.${var.tailnet_dns_name}"
}

output "node_public_ip" {
  description = "Public IP (outbound only; must answer on no port)."
  value       = oci_core_instance.node.public_ip
}

output "node_shape" {
  description = "Shape and size of the node."
  value       = "${oci_core_instance.node.shape} ${var.node_ocpus} OCPU / ${var.node_memory_gb} GB"
}

output "compartment_id" {
  description = "Compartment holding every QuantumOps resource."
  value       = oci_identity_compartment.qops.id
}

output "tailnet_dns_name" {
  description = "MagicDNS suffix; UIs exposed by the operator live at https://<name>.<this>."
  value       = var.tailnet_dns_name
}

output "k8s_operator_oauth_client_id" {
  description = "OAuth client ID for the Tailscale Kubernetes operator."
  value       = tailscale_oauth_client.k8s_operator.id
}

output "k8s_operator_oauth_client_secret" {
  description = "OAuth client secret for the Tailscale Kubernetes operator (read by make bootstrap)."
  value       = tailscale_oauth_client.k8s_operator.key
  sensitive   = true
}
