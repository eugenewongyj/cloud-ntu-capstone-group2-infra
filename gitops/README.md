# Re-register the Target into AWS NLB Target Groups

TG_32008="arn:aws:elasticloadbalancing:ap-southeast-1:255945442255:targetgroup/k8s-kubesyst-ciliumin-1fb597fa15/23aaf07d591e9f01"
TG_30138="arn:aws:elasticloadbalancing:ap-southeast-1:255945442255:targetgroup/k8s-kubesyst-ciliumin-117af638ff/2f743dd89bd8889d"

# Register to HTTP target group (port 32008)
aws elbv2 register-targets --region ap-southeast-1 \
  --target-group-arn "$TG_32008" \
  --targets Id=i-0ed271a2a116e1ae5,Port=32008

# Register to HTTPS target group (port 30138)
aws elbv2 register-targets --region ap-southeast-1 \
  --target-group-arn "$TG_30138" \
  --targets Id=i-0ed271a2a116e1ae5,Port=30138


# Verify Target Health
echo "=== HTTP (Port 32008) Target Group Health ==="
aws elbv2 describe-target-health --region ap-southeast-1 \
  --target-group-arn "$TG_32008" \
  --query "TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State]" \
  --output table

echo "=== HTTPS (Port 30138) Target Group Health ==="
aws elbv2 describe-target-health --region ap-southeast-1 \
  --target-group-arn "$TG_30138" \
  --query "TargetHealthDescriptions[*].[Target.Id,Target.Port,TargetHealth.State]" \
  --output table