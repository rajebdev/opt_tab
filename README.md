# OptTab - Lightweight Alt+Tab untuk macOS

Aplikasi pengganti Alt+Tab yang ringan, hemat memory dan CPU untuk macOS.

## 🎯 Fitur

- ⌨️  **Shortcut sederhana**: Tekan `Option+Tab` untuk switch aplikasi
- 🪶 **Ringan**: Dibangun dengan native Swift, minimal resource usage
- 🎨 **UI Modern**: Tampilan overlay yang bersih dan intuitif
- 🚀 **Performa Tinggi**: Tidak membebani CPU atau memory
- 🔒 **Privacy**: Tidak mengumpulkan data apapun

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

3. **Grant Accessibility permissions:**
   - Buka System Settings > Privacy & Security > Accessibility
   - Tambahkan Terminal atau aplikasi yang menjalankan OptTab
   - Toggle ON permission-nya

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
2. **Tekan `Option+Tab`** - Tampilan app switcher akan muncul
3. **Tekan `Tab` berkali-kali** - Cycle melalui aplikasi yang sedang berjalan
4. **Lepas `Option`** - Aplikasi yang dipilih akan diaktifkan
5. **Tekan `Esc`** - Cancel switching

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

- **Memory**: ~10-15MB (jauh lebih ringan dari Electron apps)
- **CPU**: Hampir 0% saat idle, <1% saat switching
- **Disk**: Binary hanya ~1MB setelah compile

### Tips Optimisasi

1. **Run sebagai accessory app** - Tidak muncul di Dock
2. **Lazy loading** - Window hanya dibuat saat diperlukan
3. **Efficient event monitoring** - Hanya monitor events yang diperlukan
4. **Native API** - Menggunakan Cocoa framework tanpa dependencies eksternal

## 🐛 Troubleshooting

### App tidak respond terhadap Option+Tab
- Pastikan accessibility permissions sudah diberikan
- Restart aplikasi setelah grant permissions

### Window tidak muncul
- Check Console.app untuk error messages
- Pastikan ada minimal 2 aplikasi yang running

### Build errors
- Pastikan Swift version minimal 5.9
- Update Xcode ke versi terbaru

## 📝 License

MIT License - Bebas digunakan dan dimodifikasi

## 🙏 Credits

Dibuat dengan ❤️ menggunakan Swift dan native macOS APIs

## 🔮 Future Improvements

- [ ] Custom keyboard shortcuts
- [ ] Search aplikasi by name
- [ ] Recently used sorting
- [ ] Dark/Light mode support
- [ ] Window preview thumbnails
- [ ] Multi-monitor support
- [ ] Favorit apps pinning

## 📞 Support

Jika ada issues atau questions, silakan buat GitHub issue.
