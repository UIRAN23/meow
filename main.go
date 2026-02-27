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
	"fyne.io/fyne/v2/layout"
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
	myApp := app.NewWithID("com.itoryon.imperor.v43")
	window := myApp.NewWindow("Imperor")
	window.Resize(fyne.NewSize(450, 800))

	// Техническое использование импортов для прохождения билда
	_ = image.Rect(0, 0, 0, 0)
	var _ jpeg.Options

	prefs := myApp.Preferences()
	var currentRoom, currentPass string
	var lastID int
	
	chatBox := container.NewVBox()
	chatScroll := container.NewVScroll(chatBox)
	mainList := container.NewVBox()
	mainScroll := container.NewVScroll(mainList)
	contentArea := container.NewStack()

	var refreshMainList func()

	// Поток сообщений
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
					circle := canvas.NewCircle(color.RGBA{R: 60, G: 90, B: 180, A: 255})
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

	openChat := func(name, pass string) {
		currentRoom, currentPass = name, pass
		chatBox.Objects = nil; lastID = 0
		chatUI := container.NewBorder(
			container.NewHBox(widget.NewButtonWithIcon("", theme.NavigateBackIcon(), func() {
				currentRoom = ""; refreshMainList()
			}), widget.NewLabel(name)),
			container.NewPadded(container.NewBorder(nil, nil, nil, sendBtn, msgInput)),
			nil, nil, chatScroll,
		)
		contentArea.Objects = []fyne.CanvasObject{chatUI}; contentArea.Refresh()
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
					d.Hide(); openChat(rIn.Text, pIn.Text)
				}
			}),
		)
		d = dialog.NewCustom("Новый чат", "X", container.NewPadded(content), window)
		d.Resize(fyne.NewSize(400, 700)); d.Show()
	}

	var drawer dialog.Dialog
	menuContent := container.NewVBox(
		widget.NewLabelWithStyle("IMPEROR", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
		widget.NewButtonWithIcon("Профиль", theme.AccountIcon(), func() {
			drawer.Hide()
			nick := widget.NewEntry(); nick.SetText(prefs.String("nickname"))
			dialog.ShowForm("Профиль", "Save", "Cancel", []*widget.FormItem{{Text: "Ник:", Widget: nick}}, func(ok bool) {
				if ok { prefs.SetString("nickname", nick.Text) }
			}, window)
		}),
		widget.NewButtonWithIcon("Настройки", theme.SettingsIcon(), func() { dialog.ShowInformation("!", "В разработке", window) }),
	)
	drawer = dialog.NewCustom("Меню", "Закрыть", container.NewPadded(menuContent), window)

	refreshMainList = func() {
		mainList.Objects = nil
		saved := strings.Split(prefs.String("chat_list"), "|")
		for _, s := range saved {
			if !strings.Contains(s, ":") { continue }
			p := strings.Split(s, ":")
			n, pass := p[0], p[1]
			mainList.Add(widget.NewButtonWithIcon(n, theme.MailComposeIcon(), func() { openChat(n, pass) }))
		}
		fab := widget.NewButtonWithIcon("", theme.ContentAddIcon(), showAddChat)
		fab.Importance = widget.HighImportance
		hubUI := container.NewBorder(
			container.NewHBox(widget.NewButtonWithIcon("", theme.MenuIcon(), func() { drawer.Show() }), widget.NewLabel("IMPEROR")),
			nil, nil, nil,
			container.NewStack(mainScroll, container.NewBorder(nil, container.NewHBox(layout.NewSpacer(), container.NewPadded(fab)), nil, nil)),
		)
		contentArea.Objects = []fyne.CanvasObject{hubUI}; contentArea.Refresh()
	}

	refreshMainList()
	window.SetContent(contentArea)
	window.ShowAndRun()
}
