name: Build Android APK
on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version: '1.21'

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y gcc-multilib libx11-dev libxcursor-dev libxinerama-dev libxrandr-dev libxi-dev libgl1-mesa-dev libglu1-mesa-dev imagemagick

      - name: Init Go Module
        run: |
          # Если файла go.mod нет, создаем его, чтобы Go не ругался
          if [ ! -f "go.mod" ]; then
            go mod init meow_chat
          fi
          go mod tidy

      - name: Install Fyne CLI (Correct Tool)
        run: go install fyne.io/tools/cmd/fyne@latest

      - name: Create Icon
        run: |
          # Создаем иконку, если её нет (обязательно для APK)
          if [ ! -f "Icon.png" ]; then
            convert -size 512x512 xc:black -fill white -gravity center -pointsize 200 -draw "text 0,0 'M'" Icon.png
          fi

      - name: Build APK
        run: |
          export PATH=$PATH:$(go env GOPATH)/bin
          # Собираем пакет. Теперь go.mod и Icon.png точно на месте.
          fyne package -os android -appID com.itoryon.meow

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: meow-messenger-apk
          path: "*.apk"
