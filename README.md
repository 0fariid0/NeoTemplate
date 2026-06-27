# 3x-ui Subscription Theme Pack

یک مجموعه تم مرتب و سبک برای صفحه سابسکریپشن 3x-ui / Sanaei Panel.

## نصب سریع

```bash
bash <(curl -Ls https://raw.githubusercontent.com/0fariid0/NeoTemplate/main/theme-manager/install.sh)
```

بعد از نصب، دستور زیر را بزنید:

```bash
neotemplate
```

از منو می‌توانید تم دلخواه را نصب، حذف یا آپدیت کنید.

## مسیر قالب در پنل

بعد از نصب هر تم، مسیر نصب نمایش داده می‌شود؛ معمولاً شبیه این است:

```text
/etc/3x-ui/sub_templates/neo-vibrant/
```

این مسیر را در پنل 3x-ui در بخش زیر قرار دهید:

```text
Panel Settings -> Subscription -> Sub Theme Directory
```

## نکته آپدیت

برای اینکه تغییرات جدید روی سرور اعمال شود، نسخه تم‌ها در `registry.json` و `manifest.json` بالا برده شده است. از داخل منو گزینه Upgrade Packages را بزنید یا از دستور زیر استفاده کنید:

```bash
neotemplate upgrade
```

## تم‌های موجود

- Neo Default
- Neo Eclipse
- Neo Glass
- Neo Minimal
- Neo Vibrant
- Neo Dashboard
