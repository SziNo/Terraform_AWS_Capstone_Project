# Terraform AWS Capstone Project

Skálázható és biztonságos webalkalmazás AWS-en, Terraformmal.

## Architektúra

- **VPC** – saját VPC `10.0.0.0/16` CIDR-rel.
- **Subnetek** – 3 public és 3 private subnet, 3 Availability Zone-ban.
- **Internet Gateway** – a VPC-hez csatolva.
- **NAT Gateway** – az egyik public subnetben, a private subnetek kifelé menetéhez.
- **Route table-ök** – public (IGW route) és private (NAT route).
- **Security groupok** – load balancer, application, bastion, database.
- **NACL-ok** – public és private subnet szintű szabályok.
- **Bastion host** – SSH belépési pont a public subnetben.
- **Application instance-ok** – 3 EC2 a private subnetekben, egy-egy AZ-ban.
- **Application Load Balancer** – a public subnetekben, a 3 app instance-ra irányítva.
- **Database** (opcionális) – EC2 a private subnetben.

## Költségek

> ⚠️ Mielőtt `apply`-t futtatsz: ez az infrastruktúra **nem fér bele teljesen** a free tier-be.

| Erőforrás                           | Miért kerül pénzbe                                                                              |
| ----------------------------------- | ----------------------------------------------------------------------------------------------- |
| NAT Gateway                         | Óradíj + adatátviteli díj, függetlenül a forgalomtól                                            |
| Application Load Balancer           | Óradíj, függetlenül a forgalomtól                                                               |
| Elastic IP (NAT-hoz)                | Díjat számol, amíg nincs instance-hoz rendelve, vagy ha nem free tier instance-hoz van rendelve |
| EC2 instance-ok (t3.micro/t2.micro) | Free tier alatt lehet ingyenes, de csak limitált óraszámig/hónapig                              |

Ha szünetet tartasz a projektben, futtass teardown-t (lásd lent) — a NAT Gateway és az ALB a legdrágább elemek, nincs értelme futni hagyni, amíg nem dolgozol rajta.

Ellenőrizd, mely instance típusok free tier-elegyesek a saját fiókodban/régiódban, mielőtt beállítod az `instance_type` változót:

```bash
aws ec2 describe-instance-types \
    --filters Name=free-tier-eligible,Values=true \
    --query 'InstanceTypes[*].InstanceType' \
    --output text
```

## Előfeltételek

- Terraform >= 1.16.0
- AWS CLI beállítva (`aws configure`)
- AWS key pair a régióban (pl. `szino-capstone-key`) — ha még nincs: `aws ec2 create-key-pair --key-name szino-capstone-key --query 'KeyMaterial' --output text > ~/.ssh/szino-capstone-key.pem && chmod 400 ~/.ssh/szino-capstone-key.pem`
- A saját IP-d a `terraform.tfvars`-ban (`curl -s https://checkip.amazonaws.com`)

## Fájlok

- `main.tf` – a fő erőforrások
- `variables.tf` – változók deklarációja
- `outputs.tf` – outputok
- `versions.tf` – Terraform és provider verziók, state backend
- `providers.tf` – AWS provider konfiguráció
- `locals.tf` – lokális értékek
- `data.tf` – data source-ok (AMI, AZ-k, S3 prefix list)
- `terraform.tfvars` – változók értékei (nem kerül gitbe)
- `terraform.tfvars.example` – példa értékek
- `userdata.sh` – az app instance-ok indulásakor futó script
- `db-userdata.sh.tpl` – a DB instance indulásakor futó script sablon
- `teardown.sh` – a teljes lebontást (infrastruktúra + state bucket) végző script
- `README.md` – ez a fájl

## Telepítés

1. Hozd létre a `terraform.tfvars` fájlt a projekt gyökérkönyvtárában, és töltsd ki a saját értékeiddel (régió, `allowed_ssh_cidr` a saját IP-d, `key_name` a már létező key pair neve). A `terraform.tfvars.example` mutatja a formátumot.

2. Inicializáld a Terraformot:

```bash
   terraform init
```

3. Nézd át, mi fog létrejönni, mielőtt bármit alkalmaznál:

```bash
   terraform plan
```

4. Alkalmazd:

```bash
   terraform apply
```

> ⏱️ Az `apply` lefutása után **ne tesztelj azonnal**. Az app instance-oknak idő kell, amíg a user data lefut és az nginx elindul (~1-2 perc), az ALB-nek pedig, amíg `active` állapotba kerül és az első health check-ek lefutnak (~1-2 perc). Várj 2-3 percet, mielőtt a Tesztelés szekcióval kezdenél — enélkül hamis `unhealthy`/`initial` állapotot vagy connection timeoutot kapsz, ami nem valódi hiba, csak türelmetlenség.

## Tesztelés

Minden parancsot a saját gépedről futtatsz, a projekt könyvtárából:

```bash
cd ~/codecool/Terraform_Practise/AWS_Capstone_Project
```

### 1. Target group health check

```bash
TG_ARN=$(aws elbv2 describe-target-groups --names capstone-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 describe-target-health \
    --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[].[Target.Id,TargetHealth.State]' \
    --output table
```

**Várt eredmény:** mind a 3 app instance `healthy`.

### 2. ALB forgalomteszt

```bash
ALB_DNS=$(terraform output -raw load_balancer_dns)

for i in 1 2 3 4 5 6; do curl -s http://$ALB_DNS/; echo; done
```

**Várt eredmény:** 6 sor, bennük a 3 instance ID, váltakozó sorrendben (ez bizonyítja, hogy az ALB tényleg elosztja a forgalmat).

> Ha mindegyik sor `Hello from ` és üres az instance ID, az nem hálózati hiba — a user data script valószínűleg CRLF sorvégekkel lett elmentve, ami a kimenő IMDSv2-token lekérdezést törte el. Futtasd: `dos2unix userdata.sh`, majd `terraform apply` újra.

### 3. ALB health check végpont

```bash
curl -s http://$ALB_DNS/health; echo
```

**Várt eredmény:** `OK`.

### 4. Bastion SSH

Új terminálban:

```bash
BASTION_IP=$(terraform output -raw bastion_public_ip)
ssh -i ~/.ssh/szino-capstone-key.pem ec2-user@$BASTION_IP
```

A bastionon futtatva:

```bash
hostname
curl -s https://checkip.amazonaws.com
```

**Várt eredmény:**

- `hostname`: `ip-10-0-1-230.eu-west-1.compute.internal` (public subnet tartományból)
- `checkip`: a bastion publikus IP-je, egyezik `$BASTION_IP`-vel

Hagyd nyitva ezt a terminált, a következő lépéshez is kell.

### 5. Bastionról privát subnet elérése (app instance)

Új terminálban:

```bash
BASTION_IP=$(terraform output -raw bastion_public_ip)

APP_IP_1=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=capstone-app-1" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

echo $APP_IP_1
```

**Várt eredmény:** `10.0.4.x` (private subnet CIDR-ből).

SSH a bastionon át, `ProxyCommand`-dal:

```bash
ssh -o ProxyCommand="ssh -i ~/.ssh/szino-capstone-key.pem -W %h:%p ec2-user@$BASTION_IP" \
    -i ~/.ssh/szino-capstone-key.pem ec2-user@$APP_IP_1
```

Az app instance-on futtatva:

```bash
hostname
curl -s http://localhost/health
curl -s http://localhost/
```

**Várt eredmény:**

- `hostname`: `ip-10-0-4-227...` (private subnet)
- `/health`: `OK`
- `/`: `Hello from i-...` (a saját instance ID-ja)

Hagyd nyitva ezt a terminált is.

### 6. Bastionról DB elérés (ennek TILOS sikerülnie)

A bastion termináljában:

```bash
DB_IP=$(terraform output -raw db_private_ip)
echo $DB_IP
```

**Várt eredmény:** `10.0.4.201` (private subnet).

```bash
ssh -o ConnectTimeout=5 -i ~/.ssh/szino-capstone-key.pem ec2-user@$DB_IP
```

**Várt eredmény:** timeout / megakad — a DB SG nem engedi a bastion SG-től a 22-es portot, ez a helyes viselkedés. Ha megakad: `Ctrl + C`.

### 7. DB elérés az application SG-ből

Menj vissza az app instance termináljára (5. lépés), és futtasd ott:

```bash
timeout 3 bash -c "</dev/tcp/10.0.4.201/5432" && echo "port open" || echo "port closed"
```

**Várt eredmény:** `port open` — ez bizonyítja, hogy az App SG-ből elérhető a DB 5432-es portja.

**Opcionális — tényleges adatbázis-kapcsolat:**

```bash
sudo dnf install -y postgresql15
psql -h 10.0.4.201 -U appuser -d appdb
```

A jelszót a saját gépeden, új terminálban kérdezd le:

```bash
terraform output -raw db_password
```

**Várt eredmény:** belépés az `appdb=>` promptba, `\l` listázza az `appdb`-t, `\q` a kilépés.

## Teardown

```bash
./teardown.sh
```

**Várt eredmény:**

```
Destroy complete! Resources: 43 destroyed.
Nincs szino-terraform-state bucket, kihagyom.
Teardown kész.
```

### "What is still standing" ellenőrzés

Ezeknek a parancsoknak mind **üres** eredményt kell adniuk teardown után:

```bash
# Instance-ok
aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=running,pending,shutting-down,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`].Value[0]]' \
    --output text

# NAT Gateway
aws ec2 describe-nat-gateways \
    --query 'NatGateways[?State!=`deleted`].[NatGatewayId,State]' --output text

# Elastic IP-k
aws ec2 describe-addresses \
    --query 'Addresses[].[PublicIp,InstanceId]' --output text

# Security groupok
aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=capstone-*" \
    --query 'SecurityGroups[].GroupId' --output text

# VPC
aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=capstone-vpc" \
    --query 'Vpcs[].VpcId' --output text

# Load balancer
aws elbv2 describe-load-balancers \
    --query 'LoadBalancers[].LoadBalancerName' --output text

# Target group
aws elbv2 describe-target-groups \
    --query 'TargetGroups[].TargetGroupName' --output text
```

> 💡 Ha bármelyik nem üres, nézd meg, mi maradt rajta — leggyakrabban az ALB, mert a hálózati interfészei lassabban szabadulnak fel, mint ahogy a `destroy` lefut. Pár perc múlva futtasd újra az ellenőrzést, mielőtt beavatkozol.

## Key pair — csak ha véglegesen végeztél a projekttel

A kulcspárt (ez esetben `szino-capstone-key`) AWS CLI-vel hoztuk létre, nem a Terraform kezeli — a `main.tf`-ben nincs `aws_key_pair` resource, csak egy `var.key_name` hivatkozás egy már létező kulcsra. Emiatt a `terraform destroy` / `teardown.sh` **sosem nyúl hozzá**, ez szándékos: amíg visszatérsz a projekthez, a kulcsnak életben kell maradnia, különben minden újraindításnál új kulcsot kellene generálni.

**Ha már biztosan nem lesz rá szükség**, két helyről kell törölni, külön-külön:

```bash
# AWS-ből (ezt mutatta a konzol is)
aws ec2 delete-key-pair --key-name szino-capstone-key

# Helyileg
rm -f ~/.ssh/szino-capstone-key.pem
```

> ⚠️ Ezt **ne tedd bele a `teardown.sh`-ba**, amíg aktívan dolgozol a projekten — a rendszeres teardown/újraépítés ciklushoz a kulcsnak meg kell maradnia.

## Összefoglaló táblázat

| #   | Teszt                     | Hol                       | Várt eredmény                   |
| --- | ------------------------- | ------------------------- | ------------------------------- |
| 1   | Target group health       | saját gép                 | 3× `healthy`                    |
| 2   | ALB forgalom              | saját gép                 | 6 sor, 3 különböző ID           |
| 3   | ALB `/health`             | saját gép                 | `OK`                            |
| 4   | Bastion SSH               | saját gép → bastion       | belépés, `hostname`, `checkip`  |
| 5   | App instance bastionon át | saját gép → bastion → app | belépés, `OK`, `Hello from ...` |
| 6   | DB a bastionról           | bastion → DB              | timeout (nem szabad sikerülnie) |
| 7   | DB az app-ról             | app → DB                  | `port open`                     |
| 8   | Teardown                  | saját gép                 | `43 destroyed`                  |
| 9   | "What is still standing"  | saját gép                 | minden üres                     |

Ezzel a capstone teljesen tesztelve és letakarítva van.

---

## Haladó: Remote State (S3 backend)

Alapból a Terraform helyi fájlban (`terraform.tfstate`) tárolja az állapotot. Ez gyakorláshoz megfelelő, de csapatmunkánál vagy ha több gépről dolgozol a projekten, érdemes **remote state**-re váltani — így mindenki ugyanazt a state-et látja, és nem kerül verziókezelésbe (nem is szabadna).

### Beállítás

**1. Hozz létre egy S3 bucketet CLI-ból**, ugyanabban a régióban, amit a projekt használ:

```bash
aws s3 mb s3://szino-terraform-state --region eu-west-1
```

**2. Egészítsd ki a `terraform` blokkot** (`versions.tf`-ben) egy `backend "s3"` résszel:

```hcl
terraform {
  backend "s3" {
    bucket       = "szino-terraform-state"
    key          = "capstone/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

**3. Futtasd a migrálást:**

```bash
terraform init -migrate-state
```

Ez átmásolja a jelenlegi helyi state-et az S3 bucketbe. Innentől a Terraform minden parancsnál onnan olvas és oda ír.

> Miután egy `terraform plan` hiba nélkül lefutott (ez megerősíti, hogy a remote state tényleg működik), a helyi `terraform.tfstate` és `terraform.tfstate.backup` fájlok törölhetők — már nincs rájuk szükség.

### A teardown NEM törli a state bucketet automatikusan — kivéve ha a `teardown.sh`-t használod

A sima `terraform destroy` csak azt bontja le, amit a state nyilvántart, saját magát a state-tároló bucketet nem, mert az nincs a state-ben (ez egy "tyúk vagy tojás" probléma: a backend nem kezelheti önmagát). Ha a bucketre már tényleg nincs szükség, manuálisan kell törölni:

```bash
aws s3 rb s3://szino-terraform-state --force
```

> A `--force` törli a bucketben lévő objektumokat is a bucket törlése előtt — enélkül a `rb` hibát dob, ha a bucket nem üres.
>
> A `teardown.sh` ezt automatikusan elvégzi: lefuttatja a `terraform destroy -auto-approve` parancsot, majd törli a state bucketet is.

### Ha a state bucket törlődött, miközben remote state-en voltál

```bash
# 1. Új (üres) bucket létrehozása
aws s3 mb s3://szino-terraform-state --region eu-west-1

# 2. A backend újracsatlakoztatása — state NÉLKÜL
terraform init -reconfigure
```

Mivel a state elveszett, a Terraform most azt hinné, semmi nincs még létrehozva. Két út van innen:

- **Van korábbi mentésed** (pl. egy régi `.tfstate`/`.tfstate.backup`): töltsd fel kézzel a bucketbe (`aws s3 cp terraform.tfstate.backup s3://szino-terraform-state/capstone/terraform.tfstate`), mielőtt bármit futtatnál.
- **Nincs mentésed**: erőforrásonként `terraform import`-tal visszaköthető a már létező AWS objektum az új, üres state-hez — időigényes, de nem kell mindent újraépíteni.

> **Ez pont az érv a bucket verziózására**, hogy ne kerülj ebbe a helyzetbe:
>
> ```bash
> aws s3api put-bucket-versioning --bucket szino-terraform-state \
>     --versioning-configuration Status=Enabled
> ```
>
> Ehhez nincs `s3 mb`-szerű rövidített forma, mert a versioning nem bucket-létrehozási paraméter, hanem egy külön beállítás, ezért marad `s3api`. Beállítása után egy véletlen törlés vagy felülírás esetén egyszerűen visszaállítható egy korábbi verzió, nem kell import-tal bajlódni.
