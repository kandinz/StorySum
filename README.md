# 📖 StorySum - Trình Đọc & Nghe Truyện AI Thông Minh

**StorySum** là ứng dụng di động Android chuyên dụng hỗ trợ cào nội dung truyện từ các trang web, tự động tóm tắt chương bằng AI, dịch thuật ngôn ngữ và chuyển đổi văn bản thành giọng đọc truyền cảm offline 100% theo từng câu, phát mượt mà ngay cả khi tắt màn hình.

---

## ❤️ Ủng Hộ (Donate)

Nếu bạn yêu thích ứng dụng **StorySum** và thấy ứng dụng hữu ích cho quá trình trải nghiệm đọc và nghe truyện của mình, hãy ủng hộ tác giả một ly cà phê để tiếp tục duy trì, phát triển và bổ sung thêm nhiều tính năng mới nhé!

<img src="assets/icons/donate.png" alt="Mã QR Donate" width="220" />

**Số tài khoản:** `0929672867`

*Cảm ơn sự đồng hành và ủng hộ quý báu từ bạn! ❤️*

---

## 🌟 Các Chức Năng Chính

### 1. 🌐 Cào Truyện Tự Động Từ Đường Dẫn Web

- Tự động nhận diện và trích xuất nội dung chương truyện từ đường dẫn (URL) của hầu hết các trang web truyện phổ biến.
- Tự động nhận diện số chương, tên truyện, loại bỏ quảng cáo, rác trang web và giữ lại văn bản chuẩn xác.

### 2. 🤖 Tóm Tắt Chương & Dịch Thuật Bằng AI

- **Tự động tóm tắt thông minh**: Khi chuyển sang xem tab **Tóm tắt**, hệ thống tự động kích hoạt AI để trích xuất ý chính, nhân vật và sự kiện nổi bật của chương truyện.
- **Dịch thuật đa ngôn ngữ**: Hỗ trợ dịch tự động nội dung truyện tiếng nước ngoài (tiếng Trung, Convert, tiếng Anh...) sang tiếng Việt mượt mà, thuần Việt.
- **Hỗ trợ đa nền tảng AI**: Dễ dàng cấu hình và sử dụng Google Gemini, OpenAI, Claude, DeepSeek hoặc các dịch vụ AI tùy chỉnh.

### 3. 🎙️ Giọng Đọc AI Offline 100% (ONNX TTS)

- **Hoạt động hoàn toàn không cần Internet**: Chạy trực tiếp mô hình giọng đọc AI ONNX trên chip thiết bị, đảm bảo nghe truyện mọi lúc mọi nơi mà không tốn dung lượng 4G/Wifi.
- **Tách câu thông minh**: Văn bản được tách thành từng câu độc lập. Người dùng có thể chạm vào bất kỳ câu nào để nghe phát ngay câu đó.
- **Thêm giọng đọc tùy biến**: Cho phép nhập trực tiếp file giọng đọc mô hình `.onnx` từ bộ nhớ máy.
- **Tùy chỉnh tốc độ đọc**: Linh hoạt thay đổi tốc độ đọc từ `0.5x` đến `2.0x`.

### 4. 🎧 Phát Nền Liền Mạch & Tự Chuyển Chương

- **Phát audio khi khóa màn hình**: Duy trì phát âm thanh liên tục trong nền (Foreground Service) ngay cả khi tắt màn hình điện thoại hoặc chuyển sang ứng dụng khác.
- **Tự động chuyển chương (Auto-Next)**: Tự động tải và phát tiếp chương kế tiếp khi nghe hết chương hiện tại.
- **Tải trước ngầm (Preload Audio)**: Ứng dụng tự động tải dữ liệu và tạo trước file âm thanh của chương tiếp theo trong nền để khi chuyển chương sẽ phát ngay lập tức không có độ trễ.

### 5. ⏱️ Hẹn Giờ Dừng Phát (Sleep Timer)

- Hỗ trợ các mốc thời gian hẹn giờ tiện lợi: **15 phút, 30 phút, 45 phút, 60 phút, 90 phút, 120 phút**.
- Đếm ngược thời gian thực và tự động ngắt phát âm thanh khi hết giờ, giúp người nghe yên tâm nghe truyện trước khi ngủ.

### 6. 🎨 Tùy Biến Giao Diện Đọc & Font Chữ

- **5 Theme giao diện bảo vệ mắt**: Dark (Tối), Light (Sáng), System (Theo hệ thống), Sepia (Trang sách vàng chống mỏi mắt), Warm (Ấm áp ban đêm).
- **6 Font chữ tiếng Việt sắc nét**: `Inter`, `Be Vietnam Pro`, `Lora`, `Merriweather`, `Literata`, `Roboto`.
- **Tùy chỉnh cỡ chữ**: Kéo thanh trượt để phóng to / thu nhỏ cỡ chữ đọc truyện theo nhu cầu.

### 7. 📚 Thư Viện Lưu Trữ Offline (Đã Lưu)

- Quản lý danh sách các chương và bản audio đã tạo trên máy.
- Ghi nhớ chính xác vị trí câu đang nghe dở dang để tiếp tục phát lại đúng vị trí trong lần mở tiếp theo.

---

## 📱 Hướng Dẫn Sử Dụng

### 1. Tải & Cài Đặt Ứng Dụng

1. Truy cập mục [Releases](https://github.com/kandinz/SummaryStory/releases) của dự án.
2. Tải về file cài đặt `app-arm64-v8a-release.apk` mới nhất.
3. Mở file APK trên điện thoại Android và cho phép cài đặt ứng dụng.

### 2. Cào Truyện & Đọc Chương

1. Mở ứng dụng StorySum.
2. Dán link (URL) chương truyện vào ô nhập link ở đầu màn hình và nhấn **Lấy nội dung**.
3. Ứng dụng sẽ tự động tải nội dung truyện, làm sạch văn bản và hiển thị lên màn hình.

### 3. Chuyển Đổi Qua Lại Giữa Tóm Tắt & Toàn Văn

- Nhấn vào nút tab **Tóm tắt**: Hệ thống sẽ tự động tóm tắt ý chính của chương bằng AI.
- Nhấn vào nút tab **Nội dung**: Để xem và đọc toàn văn chương truyện gốc (hoặc bản dịch).

### 4. Nghe Audio Theo Từng Câu

- **Phát từ đầu**: Bấm nút **\[ ▶ \]** (Phát) ở thanh điều khiển phía dưới màn hình. Ứng dụng sẽ phát đúng nội dung của tab bạn đang xem (Tóm tắt hoặc Nội dung).
- **Phát câu bất kỳ**: Chạm trực tiếp vào bất kỳ câu nào trong văn bản để nghe ngay câu đó.
- **Tự động cuộn**: Ứng dụng sẽ tự động đánh dấu nổi bật và cuộn màn hình theo câu đang đọc.

### 5. Chuyển Chương Nhanh

- Dùng nút **\[ &lt; \]** hoặc **\[ &gt; \]** ở thanh điều hướng dưới cùng để lùi/tiến chương.
- Nhập trực tiếp số chương vào ô nhập số chương và nhấn Enter hoặc nút tải lại để chuyển đến đúng chương mong muốn.

### 6. Cấu Hình Cài Đặt (Nút ⚙️)

Nhấn vào biểu tượng **⚙️** (Cài đặt) ở góc dưới cùng bên phải để:

- **Tab Truyện**: Chọn font chữ, theme màu giao diện, cỡ chữ hiển thị.
- **Tab Audio**: Chọn giọng đọc AI, chỉnh tốc độ đọc, bật/tắt tự động chuyển chương và đặt hẹn giờ dừng phát.
- **Tab Tóm tắt**: Cấu hình nhà cung cấp AI (Google Gemini, OpenAI...), nhập API key, tùy chỉnh prompt tóm tắt và dịch thuật.
- **Tab Donate**: Xem mã QR và số tài khoản để ủng hộ tác giả, tải ảnh mã QR về máy hoặc copy nhanh số tài khoản.