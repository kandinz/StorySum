# 📖 StorySum - Trình Đọc & Nghe Truyện AI Thông Minh

**StorySum** là ứng dụng Android chuyên dụng giúp bạn cào nội dung truyện từ web, tự động tóm tắt chương bằng AI, dịch thuật và chuyển đổi văn bản thành giọng đọc AI theo từng câu — phát mượt mà ngay cả khi tắt màn hình.

> 🔖 **Phiên bản hiện tại: v1.0.53** | Chỉ hỗ trợ Android (ARM64-v8a)

---

## ❤️ Ụng Hộ (Donate)

Nếu bạn thấy **StorySum** hữu ích, hãy ủng hộ tác giả một ly cà phê để tiếp tục phát triển thêm nhiều tính năng mới!

<img src="assets/icons/donate.png" alt="Mã QR Donate" width="220" />

**Số tài khoản:** `0929672867`

*Cảm ơn sự đồng hành và ủng hộ quý báu từ bạn! ❤️*

---

## 🌟 Tính Năng Chính

### 1. 🌐 Cào & Tải Truyện Từ Web

- **Dán link chương** trực tiếp từ URL bất kỳ của hầu hết các trang web truyện phổ biến Việt Nam (TruyenFull, WebNovel, TruyenDichMienPhi, Dtruyen...).
- **Tự động phát hiện số chương, tên truyện**, loại bỏ quảng cáo, rác HTML và giữ lại văn bản sạch.
- **Tự chuyển chương liên tiếp**: Ứng dụng tự động điều chỉnh URL sang chương kế tiếp mà không cần thao tác thủ công.

### 2. 📚 Kho Truyện (Lưu Offline)

- **Lưu truyện vào kho**: Thêm truyện bằng link URL, sau đó duyệt và tải từng chương trực tiếp trong ứng dụng.
- **Tìm kiếm truyện theo tên**: Lọc nhanh trong Kho Truyện chỉ theo tên truyện.
- **Lịch sử đã đọc**: Ghi nhớ chính xác vị trí câu đang nghe dở để tiếp tục phát lại đúng chỗ.
- **Quản lý audio đã tạo**: Xem và phát lại các file audio câu đã tổng hợp trong mục "Đã Lưu".

### 3. 🤖 Tóm Tắt & Dịch Thuật Bằng AI (Đa Nhà Cung Cấp)

- **Tự động tóm tắt thông minh**: Khi chuyển sang tab **Tóm tắt**, AI trích xuất ý chính, nhân vật và sự kiện nổi bật của chương.
- **Dịch thuật đa ngôn ngữ**: Dịch nội dung tiếng Trung, tiếng Anh... sang tiếng Việt thuần tự nhiên.
- **Hỗ trợ 7+ nhà cung cấp AI tích hợp sẵn**:

  | Nhà cung cấp | Các model tiêu biểu |
  |---|---|
  | **Google Gemini** | gemini-2.5-flash-lite, gemini-2.5-flash, gemini-2.5-pro |
  | **ChatGPT (OpenAI)** | gpt-4o-mini, gpt-4o, gpt-4.1-mini |
  | **Claude (Anthropic)** | claude-3-5-haiku, claude-3-7-sonnet |
  | **DeepSeek** | deepseek-chat, deepseek-reasoner |
  | **OpenRouter** | Hàng trăm model qua một API key |
  | **Groq** | llama-3.3-70b, mixtral-8x7b |
  | **MiMo AI** | mimo-v2, mimo-chat |
  | **Tùy chỉnh** | Bất kỳ endpoint tương thích OpenAI |

- **Hỗ trợ nhiều API key luân phiên** (round-robin): Tự động chuyển sang key tiếp theo khi hết hạn hoặc lỗi.
- **Tùy chỉnh Prompt**: Chỉnh sửa prompt tóm tắt và dịch thuật theo phong cách riêng.

### 4. 🎙️ Giọng Đọc AI Đa Nguồn

| Giọng đọc | Engine | Yêu cầu mạng |
|---|---|---|
| Ngọc Huyền | ONNX Offline | Không cần |
| Bông Cúc | ONNX Offline | Không cần |
| Hoài My | Edge TTS | Cần mạng |
| Nam Minh | Edge TTS | Cần mạng |
| Cô gái hoạt ngôn | TikTok TTS | Cần mạng |
| Cô gái ngọt ngào | TikTok TTS | Cần mạng |
| Thanh niên tự tin | TikTok TTS | Cần mạng |
| Giọng nữ phổ thông | TikTok TTS | Cần mạng |
| Giọng tùy biến | ONNX (nhập file) | Không cần |

- **Tốc độ đọc linh hoạt**: Chỉnh từ 0.5x đến 2.0x.
- **Tách câu thông minh**: Nhấn vào bất kỳ câu nào để nghe phát ngay câu đó.
- **Tự động cuộn** theo câu đang đọc.

### 5. 🎧 Phát Nền Liền Mạch & Tự Chuyển Chương

- **Phát khi khóa màn hình**: Duy trì âm thanh liên tục qua Foreground Service ngay cả khi tắt màn hình hoặc chuyển ứng dụng khác.
- **Tự chuyển chương (Auto-Next)**: Tải và phát tiếp chương kế tiếp tự động khi nghe xong chương hiện tại.
- **Tải trước ngầm (Preload)**: Tự động tạo trước file audio chương tiếp theo trong nền để chuyển chương không có độ trễ.
- **Tải nhanh câu tiếp theo (Lookahead)**: Liên tục sinh audio cho các câu sắp tới trong khi đang phát câu hiện tại.

### 6. ⏱️ Hẹn Giờ Dừng Phát (Sleep Timer)

- Các mốc thời gian tiện lợi: **15, 30, 45, 60, 90, 120 phút**.
- Đếm ngược thời gian thực, hiển thị badge ở thanh điều khiển.
- Tự động ngắt phát khi hết giờ — tiện lợi để nghe truyện trước khi ngủ.

### 7. 🎨 Tùy Biến Giao Diện

- **5 Theme bảo vệ mắt**: Dark (Tối), Light (Sáng), System (Theo hệ thống), Sepia (Trang sách vàng), Warm (Ấm áp ban đêm).
- **6 Font chữ tiếng Việt**: Inter, Be Vietnam Pro, Lora, Merriweather, Literata, Roboto.
- **Cỡ chữ tùy chỉnh**: Kéo thanh trượt phóng to/thu nhỏ chữ.

---

## 📱 Hướng Dẫn Sử Dụng

### 1. Tải & Cài Đặt

1. Vào mục [**Releases**](https://github.com/kandinz/SummaryStory/releases) của dự án.
2. Tải file `app-arm64-v8a-release.apk` phiên bản mới nhất.
3. Mở file APK trên Android và cho phép cài đặt ứng dụng từ nguồn không xác định.

---

### 2. Đọc Truyện Từ Link Web

1. Mở **StorySum**, nhập hoặc dán link (URL) chương truyện vào ô nhập link ở đầu màn hình.
2. Nhấn **Tải** → ứng dụng tự tải nội dung, làm sạch văn bản và hiển thị.
3. Dùng nút **[ < ]** / **[ > ]** hoặc nhập số chương để chuyển chương.

---

### 3. Sử Dụng Kho Truyện

1. Nhấn biểu tượng **Kho Truyện** (📚) ở góc trên để mở.
2. Nhấn **"+ Thêm Truyện"** → dán link URL trang tổng quan truyện → nhấn **Tải**.
3. Chọn truyện trong kho → chọn chương muốn đọc → nhấn **Đọc**.
4. Dùng ô tìm kiếm để lọc truyện nhanh theo tên.

---

### 4. Nghe Audio Theo Từng Câu

- **Phát từ đầu**: Nhấn nút **[ ▶ ]** ở thanh điều khiển phía dưới. Ứng dụng phát đúng nội dung của tab bạn đang xem (Tóm tắt hoặc Nội dung).
- **Phát câu bất kỳ**: Nhấn trực tiếp vào bất kỳ câu nào trong văn bản.
- **Chuyển sang Tab Tóm tắt**: AI tự động tóm tắt chương, sau đó phát audio tóm tắt.

---

### 5. Cấu Hình API Key AI (Cho Tóm Tắt và Dịch)

1. Nhấn nút **⚙️** (Cài đặt) → chọn tab **"Dịch & Tóm tắt"**.
2. Chọn **Nhà cung cấp AI** (Gemini, ChatGPT, Claude, DeepSeek...).
3. Nhập **API Key** của nhà cung cấp đã chọn (có thể thêm nhiều key để dự phòng).
4. Chọn **Model AI** phù hợp và tùy chỉnh **Prompt** nếu cần.

> 💡 **Lấy API key miễn phí**: Google Gemini tại [aistudio.google.com](https://aistudio.google.com), DeepSeek tại [platform.deepseek.com](https://platform.deepseek.com).

---

### 6. Đổi Giọng Đọc

1. Nhấn **⚙️** → tab **"Audio"**.
2. Chọn giọng đọc mong muốn từ danh sách (ONNX Offline, Edge TTS, TikTok TTS).
3. Ứng dụng tự động tải lại audio theo giọng đọc mới.
4. **Nhập giọng tùy biến**: Nhấn "Thêm giọng ONNX" và chọn file `.onnx` từ bộ nhớ máy.

---

### 7. Cài Đặt Hẹn Giờ Dừng Phát

1. Nhấn **⚙️** → tab **"Audio"** → mục **"Hẹn giờ dừng phát"**.
2. Chọn thời gian (15, 30, 45, 60, 90, 120 phút).
3. Đếm ngược hiển thị ngay trên thanh điều khiển chính.

---

## 🔧 Yêu Cầu Hệ Thống

- **Android 6.0+** (API 23 trở lên)
- **Kiến trúc**: ARM64-v8a (hầu hết điện thoại Android từ 2016 trở lên)
- **Dung lượng**: ~50 MB (bao gồm model ONNX tích hợp sẵn)
- **Kết nối Internet**: Chỉ cần khi dùng giọng TTS Online (Edge/TikTok), tóm tắt AI hoặc cào truyện từ web

---

## 📄 Giấy Phép

Dự án mã nguồn mở — phân phối theo giấy phép **MIT License**.
