# NPM Mobile Manager

A Flutter-based mobile application for managing your Nginx Proxy Manager instances on the go. This app provides a convenient way to monitor and manage your proxy hosts from your mobile device.

## YouTube Demo

![Static Badge](https://img.shields.io/badge/demo-red?link=https%3A%2F%2Fyoutube.com%2Fshorts%2FzxFZrzZiYwc%3Ffeature%3Dshare)

## Demo Credentials:
Server: Any IP
Username: demo@playstore.com
Password: demopass123

## Download

[⬇️ Download Latest APK](https://github.com/kmanan/npm-mobile/releases/latest)

## Screenshots

![image](https://github.com/user-attachments/assets/952e3700-7c7b-4df7-a688-bb14810b6c5c) ![image](https://github.com/user-attachments/assets/68af0ad6-a168-4e8e-aead-3adde0f2da40)

## About

This app is a mobile client for [Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager), an easy-to-use proxy host manager with SSL support. While the original project provides a web interface, this mobile app brings that functionality to your pocket.

Fully built using Cursor.AI

## Features

- Connect to your Nginx Proxy Manager instance
- Secure authentication
- View all proxy hosts
- Monitor proxy host status
- Save server URL for quick access
- Mobile-optimized interface

## Installation

Download the latest APK from the releases section and install it on your Android device.

### Requirements

- Android 5.0 or higher
- Active Nginx Proxy Manager instance
- Network access to your NPM server

## Usage

1. Launch the app
2. Enter your NPM server URL (e.g., `example.com:81` or `192.168.1.100:81`)
3. Log in with your NPM credentials
4. View and monitor your proxy hosts

## Building from Source

1. Clone the repository
   ```bash
   git clone https://github.com/kmanan/npm-mobile.git
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Build the release APK
   ```bash
   flutter build apk --release
   ```

## Credits

- [Nginx Proxy Manager](https://github.com/NginxProxyManager/nginx-proxy-manager) - The awesome project this app is built for
- Built with [Flutter](https://flutter.dev)
- Cursor.AI (https://cursor.ai)
- VS Code

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This is an unofficial mobile client for Nginx Proxy Manager. It is not affiliated with or endorsed by the Nginx Proxy Manager project.
