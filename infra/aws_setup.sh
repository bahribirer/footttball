#!/usr/bin/env bash
# Yeni bir AWS hesabında sunucuyu sıfırdan oluşturur.
#
#   ./infra/aws_setup.sh [bölge] [instance-tipi]
#
# Oluşturduğu kaynaklar:
#   * SSH anahtar çifti      tikitakatoe-key      (~/.ssh/tikitakatoe.pem)
#   * Güvenlik grubu         tikitakatoe-sg       (22 / 80 / 443)
#   * EC2 sunucusu           Ubuntu 24.04, 20 GB gp3
#   * Elastic IP             sunucuya bağlı       (IP artık değişmez)
#
# Betik yeniden çalıştırılabilir: var olan kaynakları yeniden oluşturmaz.
# Kurulumun devamı için `infra/provision.sh` kullanılır.

set -euo pipefail

REGION="${1:-eu-central-1}"
INSTANCE_TYPE="${2:-t3.small}"

KEY_NAME="tikitakatoe-key"
KEY_FILE="$HOME/.ssh/tikitakatoe.pem"
SG_NAME="tikitakatoe-sg"
TAG="tikitakatoe"

aws() { command aws --region "$REGION" "$@"; }

echo "▶ Hesap denetleniyor"
IDENTITY=$(aws sts get-caller-identity --output text --query 'Account' 2>/dev/null) || {
  echo "✗ AWS kimlik bilgileri yapılandırılmamış. Önce: aws configure" >&2
  exit 1
}
echo "  hesap: $IDENTITY   bölge: $REGION"

# --- SSH anahtarı -----------------------------------------------------
echo "▶ SSH anahtarı"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "  '$KEY_NAME' zaten var"
  [ -f "$KEY_FILE" ] || {
    echo "✗ Anahtar AWS'de var ama $KEY_FILE yerelde yok." >&2
    echo "  AWS konsolundan anahtarı silip betiği tekrar çalıştırın." >&2
    exit 1
  }
else
  aws ec2 create-key-pair --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "  oluşturuldu: $KEY_FILE"
fi

# --- Güvenlik grubu ---------------------------------------------------
echo "▶ Güvenlik grubu"
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [ "$SG_ID" = "None" ] || [ -z "$SG_ID" ]; then
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' --output text)
  SG_ID=$(aws ec2 create-security-group --group-name "$SG_NAME" \
    --description "Tiki Taka Toe: SSH, HTTP, HTTPS" --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)

  for PORT in 22 80 443; do
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
      --protocol tcp --port "$PORT" --cidr 0.0.0.0/0 >/dev/null
  done
  echo "  oluşturuldu: $SG_ID (22, 80, 443)"
else
  echo "  zaten var: $SG_ID"
fi

# --- Sunucu -----------------------------------------------------------
echo "▶ Sunucu"
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$TAG" "Name=instance-state-name,Values=running,pending,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "None")

if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
  # Ubuntu 24.04 AMI kimliği bölgeye göre değişir; Canonical'ın SSM kaydından alınır.
  AMI_ID=$(aws ssm get-parameters \
    --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query 'Parameters[0].Value' --output text)
  echo "  AMI: $AMI_ID"

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=20,VolumeType=gp3,DeleteOnTermination=true}' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$TAG}]" \
    --query 'Instances[0].InstanceId' --output text)
  echo "  başlatıldı: $INSTANCE_ID ($INSTANCE_TYPE)"

  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
else
  STATE=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)
  echo "  zaten var: $INSTANCE_ID ($STATE)"
  if [ "$STATE" = "stopped" ]; then
    aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    echo "  başlatıldı"
  fi
fi

# --- Elastic IP -------------------------------------------------------
# Sabit IP olmadan sunucu her yeniden başladığında adres değişir; eski
# kurulumda alan adı bu yüzden ölü bir adrese bakıyordu.
echo "▶ Elastic IP"
ALLOC_ID=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=$TAG" \
  --query 'Addresses[0].AllocationId' --output text 2>/dev/null || echo "None")

if [ "$ALLOC_ID" = "None" ] || [ -z "$ALLOC_ID" ]; then
  ALLOC_ID=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$TAG}]" \
    --query 'AllocationId' --output text)
  echo "  ayrıldı: $ALLOC_ID"
fi

aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC_ID" >/dev/null
PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" \
  --query 'Addresses[0].PublicIp' --output text)

echo
echo "════════════════════════════════════════════"
echo "  Sunucu hazır"
echo "  IP        : $PUBLIC_IP"
echo "  Bağlantı  : ssh -i $KEY_FILE ubuntu@$PUBLIC_IP"
echo "════════════════════════════════════════════"
echo
echo "Sıradaki adımlar:"
echo "  1) Alan adı DNS A kaydını $PUBLIC_IP adresine yönlendirin"
echo "     (tikitakatoe.com ve www — kayıt firması: Namecheap)"
echo "  2) Yayılmayı bekleyin, sonra:"
echo "     ./infra/provision.sh ubuntu@$PUBLIC_IP $KEY_FILE feature/game-modes-and-restructure"
