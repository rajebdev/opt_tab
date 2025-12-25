# OptTab - Lightweight Alt+Tab untuk macOS

Aplikasi pengganti Alt+Tab yang ringan, hemat memory dan CPU untuk macOS.

## 🎯 Fitur

- ⌨️  **Shortcut sederhana**: Tekan `Option+Tab` untuk switch aplikasi
- 🪶 **Ringan**: Dibangun dengan native Swift, minimal resource usage
- 🎨 **UI Modern**: Tampilan overlay yang bersih dan intuitif dengan preview windows
- 📸 **Window Thumbnails**: Preview semua windows dari setiap aplikasi secara real-time
- 🖱️ **Mouse Support**: Klik langsung pada window yang ingin diaktifkan
- ◀️▶️ **Navigasi Panah**: Tombol navigasi kiri/kanan untuk cycle antar aplikasi
- 📄 **Pagination**: Support banyak windows dengan navigation yang smooth (16 windows per halaman)
- 🎯 **Smart Filtering**: Otomatis filter windows yang valid dan dapat diakses
- 🚀 **Performa Tinggi**: Tidak membebani CPU atau memory
- 🔒 **Privacy**: Tidak mengumpulkan data apapun
- 🪟 **Multi-Window**: Deteksi dan tampilkan semua windows per aplikasi
- ⚡ **Instant Capture**: Window screenshots menggunakan CGSHWCaptureWindowList untuk performa maksimal

## 📋 Requirements

- macOS 13.0 (Ventura) atau lebih baru
- Xcode 15.0+ atau Swift 5.9+ (untuk build)

## 🚀 Cara Install & Run

### Menggunakan Swift

1. **Clone atau download project ini**

2. **Build dan run:**
   ```bash
   cd /Users/rajebdev/projects/opt_tab
   swift build
   swift run
   ```

3. **Grant Accessibility & Screen Recording permissions:**
   - Buka System Settings > Privacy & Security > Accessibility
   - Tambahkan Terminal atau aplikasi yang menjalankan OptTab
   - Toggle ON permission-nya
   - Buka System Settings > Privacy & Security > Screen Recording
   - Tambahkan Terminal atau aplikasi yang menjalankan OptTab
   - Toggle ON permission-nya (diperlukan untuk window thumbnails)

4. **Build untuk production (opsional):**
   ```bash
   swift build -c release
   ```
   
   Binary akan ada di: `.build/release/OptTab`

### Menggunakan Xcode

1. **Generate Xcode project:**
   ```bash
   swift package generate-xcodeproj
   open OptTab.xcodeproj
   ```

2. **Build dan run dari Xcode** (⌘R)

## 🎮 Cara Pakai

1. **Jalankan OptTab** - Akan muncul icon di menu bar
2. **Tekan `Option+Tab`** - Tampilan app switcher akan muncul dengan preview semua windows
3. **Navigasi dengan keyboard**:
   - Tekan `Tab` atau `→` - Cycle ke aplikasi berikutnya
   - Tekan `Shift+Tab` atau `←` - Cycle ke aplikasi sebelumnya
   - Tekan `↑` atau `↓` - Navigasi ke halaman berikutnya/sebelumnya (jika ada banyak windows)
4. **Navigasi dengan mouse**:
   - Klik pada window thumbnail - Langsung switch ke window tersebut
   - Klik tombol ◀️ atau ▶️ - Cycle antar aplikasi
5. **Lepas `Option`** - Aplikasi/window yang dipilih akan diaktifkan
6. **Tekan `Esc` atau `Q`** - Cancel switching

## 🏗️ Struktur Project

```
opt_tab/
├── Package.swift              # Swift Package Manager config
├── README.md                  # Dokumentasi ini
└── OptTab/
    └── Sources/
        ├── main.swift         # Entry point & app delegate
        ├── AppSwitcher.swift  # Logic untuk switch aplikasi & UI
        └── EventMonitor.swift # Global keyboard event monitoring
```

## 🔧 Optimisasi Resource

Aplikasi ini didesain untuk sangat ringan:

- **Memory**: ~15-25MB (jauh lebih ringan dari Electron apps)
- **CPU**: Hampir 0% saat idle, <2% saat switching dengan window capture
- **Disk**: Binary hanya ~1MB setelah compile
- **Window Capture**: Menggunakan CGSHWCaptureWindowList untuk performa optimal

### Tips Optimisasi

1. **Run sebagai accessory app** - Tidak muncul di Dock
2. **Lazy loading** - Window hanya dibuat saat diperlukan
3. **Efficient event monitoring** - Hanya monitor events yang diperlukan
4. **Native API** - Menggunakan Cocoa framework tanpa dependencies eksternal
5. **Icon caching** - App icons di-cache untuk menghindari duplicate loading
6. **Smart pagination** - Hanya render 16 windows per halaman untuk performa optimal

## 🐛 Troubleshooting

### App tidak respond terhadap Option+Tab
- Pastikan Accessibility permissions sudah diberikan
- Restart aplikasi setelah grant permissions

### Window thumbnails tidak muncul atau hitam
- Pastikan Screen Recording permissions sudah diberikan
- Check Console.app untuk error messages
- Restart aplikasi setelah grant permissions

### Window tidak muncul
- Check Console.app untuk error messages
- Pastikan ada minimal 1 window yang bisa di-capture

### Build errors
- Pastikan Swift version minimal 5.9
- Update Xcode ke versi terbaru

### Reset permissions jika ada masalah
```bash
tccutil reset Accessibility com.rajebdev.opttab
tccutil reset ScreenCapture com.rajebdev.opttab
```

## 📝 License

MIT License - Bebas digunakan dan dimodifikasi

## 🙏 Credits

Dibuat dengan ❤️ menggunakan Swift dan native macOS APIs

## 🔮 Future Improvements

- [ ] Custom keyboard shortcuts
- [ ] Search aplikasi by name
- [ ] Recently used sorting
- [ ] Dark/Light mode support
- [x] Window preview thumbnails ✅
- [x] Mouse click support ✅
- [ ] Multi-monitor support
- [ ] Favorit apps pinning
- [ ] Window grouping by app
- [ ] Customizable grid layout

## 📞 Support

Jika ada issues atau questions, silakan buat GitHub issue.
