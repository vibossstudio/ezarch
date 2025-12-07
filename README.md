# ezarch — Script cài đặt Arch Linux (TTY)

Phiên bản: 1.0

Tác giả: TYNO

---

## Mô tả

`ezarch` là một script Bash để tự động hóa việc cài đặt Arch Linux từ môi trường Arch ISO (TTY). Script được thiết kế để an toàn hơn, dừng ngay khi gặp lỗi, và có các bước xác nhận trước các thao tác huỷ dữ liệu (ví dụ: wipefs, repartitioning).

---

## Cảnh báo quan trọng

- Script này **sẽ xóa** phân vùng/ổ đĩa nếu bạn chọn chế độ tự động (auto partition). Luôn kiểm tra `DISK` trước khi xác nhận.
- Chỉ chạy script trên môi trường Live Arch (Arch ISO) với quyền `root` (TTY).
- Luôn sao lưu dữ liệu quan trọng trước khi chạy.

---

## Yêu cầu trước khi chạy

- Môi trường: Arch Linux live ISO (boot vào TTY)
- Quyền: `root` (khởi động từ live media hoặc sudo chuyển thành root)
- Công cụ tối thiểu cần có: `parted`, `sgdisk`, `wipefs`, `mkfs.*`, `mkswap`, `swapon`, `pacstrap`, `genfstab`, `arch-chroot`, `pacman`, `git`, `makepkg`.
- Kết nối mạng hoạt động để tải gói.

---

## Cách sử dụng cơ bản

1. Chuẩn bị môi trường: boot vào Arch live ISO và mở TTY (ví dụ: Ctrl+Alt+F2).
2. Clone repository hoặc sao chép `install.sh` vào live environment.

```bash
git clone https://github.com/dhungx/ezarch.git
cd ezarch
```

3. Cấp quyền và chạy script
```bash
chmod +x install.sh
sudo ./install.sh
```

Script sẽ hỏi bạn một số thông tin (ví dụ: chọn ổ đĩa, loại phân vùng, hostname, tên người dùng). Script bao gồm bước xác nhận trước khi thực hiện các thao tác huỷ dữ liệu.

---

## Ví dụ câu trả lời khi script hỏi (mẫu)

Dưới đây là bảng ví dụ cho những câu hỏi thường gặp khi chạy `install.sh`. Những giá trị này chỉ để minh họa — thay bằng thông tin phù hợp với hệ của bạn.

| Câu hỏi | Ví dụ câu trả lời | Ghi chú |
|---|---|---|
| Chọn ổ đĩa (Disk) | `/dev/sda` hoặc `/dev/nvme0n1` | Kiểm tra chính xác thiết bị trước khi xác nhận |
| Chế độ phân vùng tự động (auto partition) | `y` / `n` | `y` để tự động phân vùng, `n` để làm thủ công |
| Kiểu hệ thống tập tin (filesystem) | `ext4`, `btrfs`, `xfs`, `f2fs` | Chọn theo nhu cầu (btrfs cho snapshot, ext4 truyền thống) |
| Hostname (tên máy) | `archbox` | Không dùng dấu cách hoặc ký tự đặc biệt |
| Tên người dùng (username) | `tyno` | Chỉ chữ thường, không dấu cách |
| Mật khẩu (root/người dùng) | (nhập mật khẩu an toàn) | Dùng mật khẩu mạnh; không dùng mẫu công khai |
| Timezone | `Asia/Ho_Chi_Minh` | Xem `timedatectl list-timezones` để chọn đúng |
| Locale | `en_US.UTF-8` hoặc `vi_VN.UTF-8` | Chọn UTF-8 để tránh lỗi mã hóa |
| Keymap bàn phím | `us` hoặc `vn` | Tùy bàn phím vật lý của bạn |
| Kích thước swap (MB) | `2048` hoặc `0` | `0` để vô hiệu hoá swap; nhập số nguyên MB |
| Môi trường đồ họa (Desktop) | `none`, `xfce`, `gnome`, `plasma` | `none` nếu chỉ muốn hệ CLI |
| Cài AUR helper | `y` / `n` | Cần `base-devel` và `git` nếu chọn `y` |
| Xác nhận thao tác huỷ dữ liệu | `y` / `n` | RẤT QUAN TRỌNG — kiểm tra `DISK` trước khi `y` |

Ví dụ chuỗi tương tác (mục đích minh họa):

```text
Select disk [/dev/sda]: /dev/sda
Auto-partition? (y/n): y
Filesystem for root (/): ext4
Create swap? (MB, 0 to disable): 2048
Hostname: archbox
Username: tyno
Timezone [Region/City]: Asia/Ho_Chi_Minh
Locale (e.g. en_US.UTF-8): en_US.UTF-8
Install desktop environment (none/xfce/gnome/plasma): xfce
Install AUR helper? (y/n): y
Confirm: This will wipe /dev/sda. Continue? (y/n): y
```

Lưu ý: Luôn kiểm tra kỹ `DISK` và xác nhận rằng bạn đang thao tác trên đúng thiết bị trước khi trả lời `y` cho các câu hỏi huỷ dữ liệu.

## Tuỳ biến nhanh

- Nếu bạn muốn sửa các gói sẽ cài, mở `install.sh` và tìm mảng `packages` hoặc tên biến tương tự (đã tổ chức thành các mảng trong script).
- Swap size: script có validation để nhận giá trị hợp lệ; nhập số nguyên (MB) khi được yêu cầu.

---

## Kiểm tra sau khi cài

Sau khi quá trình cài hoàn tất và boot vào hệ mới, bạn có thể kiểm tra:

- Kiểm tra file hệ (`/etc/fstab`) đã được tạo bởi script:

```bash
cat /etc/fstab
```

- Kiểm tra gói đã cài:

```bash
pacman -Qi base
```

---

## Gợi ý an toàn và debug

- Để thử nghiệm script an toàn, bạn có thể dùng một ổ đĩa ảo (file loopback) hoặc VM để tránh rủi ro mất dữ liệu trên máy thật.
- Nếu script dừng do lỗi, xem thông báo lỗi trên STDOUT/STDERR; script đặt `set -euo pipefail` và có trap để dọn dẹp mount.
- Nếu bạn muốn chạy script theo chế độ không tương tác (không khuyến nghị), bạn phải mở rộng script và thêm cờ non-interactive; lưu ý điều này có thể gây mất dữ liệu nếu không chính xác.

---

## Ghi chú kỹ thuật ngắn

- Script đã được chỉnh sửa để:
  - Dừng khi gặp lỗi (`set -euo pipefail`) và có trap lỗi.
  - Kiểm tra các công cụ bắt buộc trước khi tiếp tục.
  - Di chuyển ghi sudoers vào `/etc/sudoers.d/` thay vì sửa trực tiếp `/etc/sudoers`.
  - Sử dụng mảng cho danh sách gói để tránh word-splitting.
  - Thêm xác nhận trước thao tác huỷ dữ liệu.

---

## Đóng góp

Mọi pull request hoặc issue xin gửi về repository `dhungx/ezarch` (nhánh `main`). Khi gửi issue, vui lòng kèm bước tái hiện và log (nếu có).

---

## License

Xin để trống hoặc bổ sung theo ý tác giả. (Nếu muốn, thêm file `LICENSE` vào repo.)

---

## Liên hệ

Tác giả: TYNO

Cảm ơn bạn đã sử dụng script!
