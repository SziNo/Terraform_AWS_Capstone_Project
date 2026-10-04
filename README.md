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

## Előfeltételek

- Terraform >= 1.16.0
- AWS CLI beállítva (`aws configure`)
- AWS key pair a régióban (pl. `szino-capstone-key`)
- A saját IP-d a `terraform.tfvars`-ban

## Fájlok

- `main.tf` – a fő erőforrások
- `variables.tf` – változók deklarációja
- `outputs.tf` – outputok
- `versions.tf` – Terraform és provider verziók
- `providers.tf` – AWS provider konfiguráció
- `locals.tf` – lokális értékek
- `data.tf` – data source-ok (AMI, AZ-k)
- `terraform.tfvars` – változók értékei (nem kerül gitbe)
- `terraform.tfvars.example` – példa értékek
- `README.md` – ez a fájl

## Költségek

Ez az infrastruktúra **nem fér bele teljesen** a free tier-be — van benne néhány óradíjas elem:

| Erőforrás                           | Miért kerül pénzbe                                                                              |
| ----------------------------------- | ----------------------------------------------------------------------------------------------- |
| NAT Gateway                         | Óradíj + adatátviteli díj, függetlenül a forgalomtól                                            |
| Application Load Balancer           | Óradíj, függetlenül a forgalomtól                                                               |
| Elastic IP (NAT-hoz)                | Díjat számol, amíg nincs instance-hoz rendelve, vagy ha nem free tier instance-hoz van rendelve |
| EC2 instance-ok (t3.micro/t2.micro) | Free tier alatt lehet ingyenes, de csak limitált óraszámig/hónapig                              |

Ha szünetet tartasz a projektben, futtass `terraform destroy`-t — a NAT Gateway és az ALB a legdrágább elemek, és nincs értelme futni hagyni, amíg nem dolgozol rajta.

## State

Alapból a Terraform helyi fájlban (`terraform.tfstate`) tárolja az állapotot. Ez gyakorláshoz megfelelő, de csapatmunkánál vagy ha több gépről dolgozol a projekten, érdemes **remote state**-re váltani — így mindenki ugyanazt a state-et látja, és nem kerül verziókezelésbe (nem is szabadna).

### Remote state beállítása (S3 backend)

**1. Hozz létre egy S3 bucketet CLI-ból**, ugyanabban a régióban, amit a projekt használ, például:

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
  }
}
```

**3. Futtasd a migrálást:**

```bash
terraform init -migrate-state
```

Ez átmásolja a jelenlegi helyi state-et az S3 bucketbe. Innentől a Terraform minden parancsnál onnan olvas és oda ír.

> Miután egy `terraform plan` hiba nélkül lefutott (ez megerősíti, hogy a remote state tényleg működik), a helyi `terraform.tfstate` és `terraform.tfstate.backup` fájlok törölhetők — már nincs rájuk szükség.

### A `terraform destroy` NEM törli a state bucketet

A `destroy` csak azt bontja le, amit a state nyilvántart, saját magát a state-tároló bucketet nem, mert az nincs a state-ben (ez egy "tyúk vagy tojás" probléma: a backend nem kezelheti önmagát). Ha a bucketre már tényleg nincs szükség, manuálisan kell törölni:

```bash
aws s3 rb s3://szino-terraform-state --force
```

> A `--force` törli a bucketben lévő objektumokat is a bucket törlése előtt — enélkül a `rb` hibát dob, ha a bucket nem üres (az `s3api`-s verziónál ezt a `s3 rm --recursive` + `s3api delete-bucket` két lépése végezte el).

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

```bash
# Ingyenes Instance-ok ellenőrzése AWS CLI-ban
aws ec2 describe-instance-types \
    --filters Name=free-tier-eligible,Values=true \
    --query 'InstanceTypes[*].InstanceType' \
    --output text
```
