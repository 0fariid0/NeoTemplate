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

## دو نسخه Neo Smart

دو نسخه مستقل در رجیستری قرار گرفته است:

- `Neo Smart` با شناسه `neo-smart`: نسخه پایدار بدون نمودار که به تغییر backend پنل نیاز ندارد.
- `Neo Smart Usage` با شناسه `neo-smart-usage`: نسخه دارای نمودار مصرف ۲۴ ساعت و ۳۰ روز که به پچ backend پنل نیاز دارد.

نصب مستقیم نسخه معمولی:

```bash
neotemplate install neo-smart
```

نصب مستقیم نسخه نمودار‌دار:

```bash
neotemplate install neo-smart-usage
```

این دو تم مستقل نصب و آپدیت می‌شوند و فایل‌های یکدیگر را جایگزین نمی‌کنند.

> Happ: Neo Smart and Neo Smart Usage include direct Android APK download, Windows x64 download, and direct subscription import via `happ://add/`. v2rayNG downloads are resolved automatically from the latest GitHub release to the matching Android ABI without opening the Releases page.
