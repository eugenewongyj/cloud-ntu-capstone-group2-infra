resource "aws_secretsmanager_secret" "sre_controller_auth" {
  name                    = "${var.project_name}/sre/controller-auth"
  description             = "Service authentication for Capstone SRE controller"
  recovery_window_in_days = 7

  tags = {
    ManagedBy = "Terraform"
    Component = "SRE"
  }
}
