# How to use

## Debian/Ubuntu

```bash
api_url="https://api.github.com/repos/zijiren233/xanmod-arm64/releases/latest"

release_info=$(curl -s "$api_url")
headers_url=$(echo "$release_info" | grep -o '"browser_download_url": "[^"]*linux-headers[^"]*"' | cut -d '"' -f 4)
image_url=$(echo "$release_info" | grep -o '"browser_download_url": "[^"]*linux-image[^"]*"' | cut -d '"' -f 4)

mkdir -p /tmp/xanmod
rm -rf /tmp/xanmod/*
curl -L -o /tmp/xanmod/linux-headers.deb "$headers_url"
curl -L -o /tmp/xanmod/linux-image.deb "$image_url"
dpkg -i /tmp/xanmod/linux-*.deb
rm -rf /tmp/xanmod
```

<!--
## Other

```bash
api_url="https://api.github.com/repos/zijiren233/xanmod-arm64/releases/latest"

release_info=$(curl -s "$api_url")
kernel_url=$(echo "$release_info" | grep -o '"browser_download_url": "[^"]*kernel-[^"]*"' | cut -d '"' -f 4)
mkdir -p /tmp/xanmod
rm -rf /tmp/xanmod/*
curl -L -o /tmp/xanmod/kernel.tar.gz2 "$kernel_url"
tar --no-same-owner -xzvf /tmp/xanmod/kernel.tar.gz2 -C /
cd /boot
for v in $(ls vmlinuz-* | sed s/vmlinuz-//g); do
    mkinitramfs -k -o initrd.img-${v} ${v}
done
update-grub
rm -rf /tmp/xanmod
```
-->
