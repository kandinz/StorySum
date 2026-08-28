# Quy Chuẩn Thiết Kế Giao Diện Cài Đặt (UI Settings)

Tài liệu này quy định các tiêu chuẩn bắt buộc khi thiết kế và cập nhật giao diện Cài đặt (Settings Modal / Screen) trong ứng dụng SummaryStory.

---

## 1. Nguyên Tắc Ngắn Gọn & Trực Quan (Concise & Clear)
- **Ưu tiên từ ngữ ngắn gọn, rõ nghĩa**: Tiêu đề mỗi mục cài đặt phải súc tích, dễ hiểu ngay từ cái nhìn đầu tiên (ví dụ: *"Số câu tải trước audio"*, *"Tự chuyển chương"*, *"Hẹn giờ dừng phát"*, *"Tốc độ đọc"*).
- **Không thêm description giải thích rườm rà**: Tuyệt đối không chèn thêm các dòng văn bản phụ (subtitle / description / caption) bên dưới tiêu đề để giải thích dài dòng cách hoạt động của tính năng, nhằm giữ cho giao diện luôn gọn gàng, thoáng đãng và thanh lịch.

---

## 2. Bố Cục Thẻ Gom Nhóm (Grouped Cards)
- **Gộp các tính năng liên quan vào chung 1 nhóm**: Các tùy chọn có cùng nhóm nghiệp vụ (ví dụ: tự động & hẹn giờ, kiểu hiển thị truyện, cấu hình AI) phải được đặt trong cùng một khung Card bo góc (`BorderRadius.circular(10)`).
- **Phân tách tinh tế bằng Divider**: Giữa các mục con trong cùng một Card sử dụng `Divider` thanh mảnh (độ mờ nhẹ `colors.border`, khoảng cách `height: 14`) thay vì chia thành nhiều block tách rời.

---

## 3. Điều Khiển Nhỏ Gọn & Chuẩn Hóa
- **Stepper & Switch đồng bộ**:
  - Số đếm (như số câu tải trước, cỡ chữ): Dùng bộ nút stepper `[-] [ Giá trị ] [+]` gọn gàng, bấm vào giá trị để mở dialog nhập số nhanh.
  - Bật/Tắt tính năng: Dùng Checkbox hoặc Switch có nhãn nằm ngang cùng dòng.
- **Giá trị hiển thị trên Header (Trailing badge)**:
  - Nếu mục cài đặt có giá trị (như tốc độ `1.0x`, cỡ chữ `15px`), hiển thị badge nhỏ gọn bên phải tiêu đề mục.
