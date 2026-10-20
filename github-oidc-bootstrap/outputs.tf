
output "infra_deployer_role_arn" {
  description = "Use as OIDC_ROLE in the group2-infra repo"
  value       = aws_iam_role.infra_deployer_role.arn
}

output "app_deployer_role_arn" {
  description = "Use as OIDC_ROLE in the group2-app repo"
  value       = aws_iam_role.app_deployer_role.arn
}
