# Upstream controller v3.6.2 IAM policy, retained with source in DOC.md.
resource "aws_iam_role" "ingress" {
  permissions_boundary = "arn:aws:iam::${var.account_id}:policy/commerce-aws-ingress-boundary"
  name                 = "${var.name}-ingress"
  assume_role_policy   = local.pod_trust
}
resource "aws_iam_role_policy" "ingress" {
  role   = aws_iam_role.ingress.id
  policy = var.load_balancer_policy_json
}
resource "aws_eks_pod_identity_association" "ingress" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.ingress.arn
}
