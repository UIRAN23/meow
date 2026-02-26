package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout" // Добавлен пропущенный пакет
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

const (
	supabaseURL = "https://ilszhdmqxsoixcefeoqa.supabase.co"
	supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc"
)

type Message struct {
	ID           int    `json:"id"`
	Sender       string `json:"sender"`
	ChatKey      string `json:"chat_key"`
	Payload      string `json:"payload"`
	SenderAvatar string `json:"sender_avatar"`
}

func fastCrypt(text, key string, decrypt bool) string {
	if len(text) < 16 && decrypt { return text }
	hKey := make([]byte, 32); copy(hKey, key)
	block, _ := aes.NewCipher(hKey)
	if decrypt {
		data, _ := base64.StdEncoding.DecodeString(text)
		if len(data) < 16 { return text }
		iv, ct := data[:16], data[16:]
		stream := cipher.NewCTR(block, iv)
		stream.XORKeyStream(ct, ct)
		return string(ct)
	}
	ct := make([]byte, 16+len(text))
	iv := ct[:16]; io.ReadFull(rand.Reader, iv)
	stream := cipher.NewCTR(block, iv)
	stream.XORKeyStream(ct[16:], []byte(text))
	return base64.StdEncoding.EncodeToString(ct)
}

func main() {
	myApp := app.NewWithID("com.itoryon.imperor.v40")
	window := myApp.NewWindow("Imperor")
	window.Resize(fyne.NewSize(450, 800))

	prefs := myApp.Preferences()
	var currentRoom, currentPass string
	var lastID int
	
	chatBox := container.NewVBox()
	chatScroll := container.NewVScroll(chatBox)

	go func() {
		for {
			if currentRoom == "" { time.Sleep(time.Second); continue }
			url := fmt.Sprintf("%s/rest/v1/messages?chat_key=eq.%s&id=gt.%d&order=id.asc&limit=30", supabaseURL, currentRoom, lastID)
			req, _ := http.NewRequest("GET", url, nil)
			req.Header.Set("apikey", supabaseKey)
			req.Header.Set("Authorization", "Bearer "+supabaseKey)
			resp, err := (&http.Client{Timeout: 5 * time.Second}).Do(req)
			if err == nil && resp.StatusCode == 200 {
				var msgs []Message
				json.NewDecoder(resp.Body).Decode(&msgs)
				resp.Body.Close()
				for _, m := range msgs {
					lastID = m.ID
					txt := fastCrypt(m.Payload, currentPass, true)
					circle := canvas.NewCircle(color.RGBA{R: 80, G: 120, B: 200, A: 255})
					circle.StrokeWidth = 1; circle.StrokeColor = color.White
					avatar := container.NewGridWrap(fyne.NewSize(36, 36), circle)
					chatBox.Add(container.NewHBox(avatar, container.NewVBox(
						canvas.NewText(m.Sender, theme.DisabledColor()), 
						widget.NewLabel(txt),
					)))
				}
				chatBox.Refresh(); chatScroll.ScrollToBottom()
			}
			time.Sleep(3 * time.Second)
		}
	}()

	msgInput := widget.NewEntry()
	msgInput.SetPlaceHolder("Написать...")
	sendBtn := widget.NewButtonWithIcon("", theme.MailSendIcon(), func() {
		if msgInput.Text == "" || currentRoom == "" { return }
		t := msgInput.Text; msgInput.SetText("")
		go func() {
			m := Message{
				Sender: prefs.StringWithFallback("nickname", "User"),
				ChatKey: currentRoom,
				Payload: fastCrypt(t, currentPass, false),
				SenderAvatar: prefs.String("avatar_data"),
			}
			b, _ := json.Marshal(m)
			req, _ := http.NewRequest("POST", supabaseURL+"/rest/v1/messages", bytes.NewBuffer(b))
			req.Header.Set("apikey", supabaseKey)
			req.Header.Set("Authorization", "Bearer "+supabaseKey)
			req.Header.Set("Content-Type", "application/json")
			(&http.Client{}).Do(req)
		}()
	})

	showProfile := func() {
		nickIn := widget.NewEntry()
		nickIn.SetText(prefs.String("nickname"))
		btnImg := widget.NewButton("Фото", func() {
			dialog.ShowFileOpen(func(r fyne.URIReadCloser, _ error) {
				if r == nil { return }
				data, _ := io.ReadAll(r); img, _, _ := image.Decode(bytes.NewReader(data))
				var buf bytes.Buffer
				jpeg.Encode(&buf, img, &jpeg.Options{Quality: 25})
				prefs.SetString("avatar_data", base64.StdEncoding.EncodeToString(buf.Bytes()))
			}, window)
		})
		d := dialog.NewCustom("Профиль", "OK", container.NewVBox(nickIn, btnImg, widget.NewButton("Save", func() { prefs.SetString("nickname", nickIn.Text) })), window)
		d.Resize(fyne.NewSize(400, 600)); d.Show()
	}

	showAddChat := func() {
		rIn, pIn := widget.NewEntry(), widget.NewEntry()
		var d dialog.Dialog
		content := container.NewVBox(
			widget.NewLabel("ID комнаты:"), rIn,
			widget.NewLabel("Ключ:"), pIn,
			widget.NewButton("ВОЙТИ", func() {
				if rIn.Text != "" {
					list := prefs.String("chat_list")
					if !strings.Contains(list, rIn.Text+":") {
						prefs.SetString("chat_list", list+"|"+rIn.Text+":"+pIn.Text)
					}
					currentRoom, currentPass = rIn.Text, pIn.Text
					chatBox.Objects = nil; lastID = 0; chatBox.Refresh(); d.Hide()
				}
			}),
		)
		d = dialog.NewCustom("Новый чат", "X", container.NewPadded(content), window)
		d.Resize(fyne.NewSize(400, 700)); d.Show()
	}

	var drawer dialog.Dialog
	showDrawer := func() {
		chatList := container.NewVBox()
		for _, c := range strings.Split(prefs.String("chat_list"), "|") {
			if !strings.Contains(c, ":") { continue }
			p := strings.Split(c, ":")
			name, pass := p[0], p[1]
			chatList.Add(widget.NewButton(name, func() {
				currentRoom, currentPass = name, pass
				chatBox.Objects = nil; lastID = 0; chatBox.Refresh(); drawer.Hide()
			}))
		}
		menu := container.NewVBox(
			widget.NewLabelWithStyle("MENU", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
			widget.NewButton("Профиль", func() { drawer.Hide(); showProfile() }),
			widget.NewButton("Настройки", func() { dialog.ShowInformation("!", "В разработке", window) }),
			widget.NewSeparator(),
			container.NewVScroll(chatList),
		)
		drawer = dialog.NewCustom("Imperor", "X", container.NewPadded(menu), window)
		drawer.Resize(fyne.NewSize(320, 800)); drawer.Show()
	}

	fab := widget.NewButtonWithIcon("", theme.ContentAddIcon(), showAddChat)
	fab.Importance = widget.HighImportance

	// Слои интерфейса
	mainUI := container.NewBorder(
		container.NewHBox(widget.NewButtonWithIcon("", theme.MenuIcon(), showDrawer), widget.NewLabel("Imperor")),
		container.NewPadded(container.NewBorder(nil, nil, nil, sendBtn, msgInput)),
		nil, nil,
		chatScroll,
	)

	// Позиционируем FAB через Spacer-ы, чтобы он был в углу, но над вводом
	fabLayer := container.NewBorder(nil, container.NewHBox(layout.NewSpacer(), container.NewPadded(fab)), nil, nil)

	window.SetContent(container.NewStack(mainUI, fabLayer))
	window.ShowAndRun()
}
