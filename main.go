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
	"image/jpeg"
	_ "image/png"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

const (
	supabaseURL = "https://ilszhdmqxsoixcefeoqa.supabase.co"
	supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc"
)

type Message struct {
	ID           int    `json:"id,omitempty"`
	Sender       string `json:"sender"`
	ChatKey      string `json:"chat_key"`
	Payload      string `json:"payload"`
	SenderAvatar string `json:"sender_avatar"`
}

var (
	lastMsgID   int
	avatarCache = make(map[string]fyne.CanvasObject)
)

// Оптимизированный дешифратор
func decrypt(cryptoText, key string) string {
	if len(cryptoText) < 16 { return cryptoText }
	fixedKey := make([]byte, 32); copy(fixedKey, key)
	ciphertext, err := base64.StdEncoding.DecodeString(cryptoText)
	if err != nil { return "[Ошибка]" }
	block, _ := aes.NewCipher(fixedKey)
	iv := ciphertext[:aes.BlockSize]; ciphertext = ciphertext[aes.BlockSize:]
	stream := cipher.NewCFBDecrypter(block, iv)
	stream.XORKeyStream(ciphertext, ciphertext)
	return string(ciphertext)
}

func encrypt(text, key string) string {
	fixedKey := make([]byte, 32); copy(fixedKey, key)
	block, _ := aes.NewCipher(fixedKey)
	ciphertext := make([]byte, aes.BlockSize+len(text))
	iv := ciphertext[:aes.BlockSize]; io.ReadFull(rand.Reader, iv)
	stream := cipher.NewCFBEncrypter(block, iv)
	stream.XORKeyStream(ciphertext[aes.BlockSize:], []byte(text))
	return base64.StdEncoding.EncodeToString(ciphertext)
}

func getAvatar(base64Str string) fyne.CanvasObject {
	if base64Str == "" { return canvas.NewImageFromResource(theme.AccountIcon()) }
	if obj, ok := avatarCache[base64Str]; ok { return obj }
	data, _ := base64.StdEncoding.DecodeString(strings.Split(base64Str, ",")[1])
	img := canvas.NewImageFromReader(bytes.NewReader(data), "a.jpg")
	img.SetMinSize(fyne.NewSize(40, 40))
	avatarCache[base64Str] = img
	return img
}

func main() {
	os.Setenv("FYNE_SCALE", "1.1")
	myApp := app.NewWithID("com.itoryon.meow.v14")
	window := myApp.NewWindow("Meow")
	window.Resize(fyne.NewSize(500, 800))

	prefs := myApp.Preferences()
	var currentRoom, currentPass string
	
	messageBox := container.NewVBox()
	chatScroll := container.NewVScroll(messageBox)
	msgInput := widget.NewEntry()
	msgInput.SetPlaceHolder("Сообщение...")

	// ГЛАВНЫЙ ЦИКЛ ОБНОВЛЕНИЯ
	go func() {
		for {
			if currentRoom == "" { time.Sleep(time.Second); continue }
			url := fmt.Sprintf("%s/rest/v1/messages?chat_key=eq.%s&id=gt.%d&order=id.asc", supabaseURL, currentRoom, lastMsgID)
			req, _ := http.NewRequest("GET", url, nil)
			req.Header.Set("apikey", supabaseKey)
			req.Header.Set("Authorization", "Bearer "+supabaseKey)
			resp, err := (&http.Client{Timeout: 4 * time.Second}).Do(req)
			if err == nil && resp.StatusCode == 200 {
				var msgs []Message
				json.NewDecoder(resp.Body).Decode(&msgs)
				resp.Body.Close()
				for _, m := range msgs {
					if m.ID > lastMsgID {
						lastMsgID = m.ID
						txt := decrypt(m.Payload, currentPass)
						
						// Верстка сообщения: иконка + (Ник + Текст)
						// Используем фиксированный размер для аватара, чтобы текст не прыгал
						av := getAvatar(m.SenderAvatar)
						av.SetMinSize(fyne.NewSize(40, 40))
						
						name := widget.NewLabelWithStyle(m.Sender, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
						content := widget.NewLabel(txt)
						content.Wrapping = fyne.TextWrapWord // Перенос по словам, а не по буквам!
						
						bubble := container.NewVBox(name, content)
						// Border растягивает центральный элемент (текст) на всю доступную ширину
						row := container.NewBorder(nil, nil, av, nil, bubble)
						
						messageBox.Add(container.NewPadded(row))
					}
				}
				chatScroll.ScrollToBottom()
			}
			time.Sleep(2 * time.Second)
		}
	}()

	// ФУНКЦИЯ ПРОФИЛЯ
	showProfile := func() {
		nickEntry := widget.NewEntry()
		nickEntry.SetText(prefs.String("nickname"))
		nickEntry.SetPlaceHolder("Ваш ник...")
		
		var avatarView *canvas.Image
		if prefs.String("avatar_base64") != "" {
			data, _ := base64.StdEncoding.DecodeString(strings.Split(prefs.String("avatar_base64"), ",")[1])
			avatarView = canvas.NewImageFromReader(bytes.NewReader(data), "p.jpg")
		} else {
			avatarView = canvas.NewImageFromResource(theme.AccountIcon())
		}
		avatarView.FillMode = canvas.ImageFillContain
		avatarView.SetMinSize(fyne.NewSize(120, 120))

		profileContent := container.NewVBox(
			container.NewCenter(avatarView),
			widget.NewButton("Выбрать фото", func() {
				dialog.ShowFileOpen(func(r fyne.URIReadCloser, e error) {
					if r == nil { return }
					d, _ := io.ReadAll(r)
					img, _, _ := image.Decode(bytes.NewReader(d))
					var buf bytes.Buffer
					jpeg.Encode(&buf, img, &jpeg.Options{Quality: 20})
					s := "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString(buf.Bytes())
					prefs.SetString("avatar_base64", s)
					// Сразу обновляем превью
					avatarView.Image = img
					avatarView.Refresh()
				}, window)
			}),
			nickEntry,
			widget.NewButtonWithIcon("Сохранить", theme.DocumentSaveIcon(), func() {
				prefs.SetString("nickname", nickEntry.Text)
				dialog.ShowInformation("Успех", "Профиль сохранен!", window)
			}),
		)
		dialog.ShowCustom("Мой Профиль", "Закрыть", profileContent, window)
	}

	// ВЫДВИЖНОЕ МЕНЮ (Drawer)
	drawer := container.NewVBox(
		widget.NewLabelWithStyle("MEOW MENU", fyne.TextAlignCenter, fyne.TextStyle{Bold: true}),
		widget.NewButtonWithIcon("Мой Профиль", theme.AccountIcon(), showProfile),
		widget.NewButtonWithIcon("Настройки", theme.SettingsIcon(), func() {
			dialog.ShowInformation("Настройки", "Тут скоро что-то будет...", window)
		}),
		widget.NewSeparator(),
		widget.NewLabel("ВАШИ ЧАТЫ:"),
	)

	// Список чатов в меню
	refreshChats := func() {
		// Очищаем и добавляем заново (кроме первых 5 элементов меню)
		for len(drawer.Objects) > 5 { drawer.Remove(drawer.Objects[5]) }
		
		list := strings.Split(prefs.StringWithFallback("chat_list", ""), ",")
		for _, s := range list {
			if !strings.Contains(s, ":") { continue }
			p := strings.Split(s, ":")
			name, pass := p[0], p[1]
			drawer.Add(widget.NewButton(name, func() {
				messageBox.Objects = nil
				lastMsgID = 0
				currentRoom, currentPass = name, pass
			}))
		}
		drawer.Add(widget.NewButtonWithIcon("Добавить чат", theme.ContentAddIcon(), func() {
			id, ps := widget.NewEntry(), widget.NewPasswordEntry()
			dialog.ShowForm("Новый чат", "ОК", "Нет", []*widget.FormItem{
				{Text: "ID", Widget: id}, {Text: "Pass", Widget: ps},
			}, func(b bool) {
				if b {
					prefs.SetString("chat_list", prefs.String("chat_list")+","+id.Text+":"+ps.Text)
				}
			}, window)
		}))
	}

	menuBtn := widget.NewButtonWithIcon("", theme.MenuIcon(), func() {
		refreshChats()
		dialog.ShowCustomSide("Меню", "Закрыть", container.NewVScroll(drawer), window)
	})

	// ОТПРАВКА
	sendBtn := widget.NewButtonWithIcon("", theme.MailSendIcon(), func() {
		if msgInput.Text == "" || currentRoom == "" { return }
		t := msgInput.Text; msgInput.SetText("")
		go func() {
			m := Message{
				Sender: prefs.StringWithFallback("nickname", "Аноним"),
				ChatKey: currentRoom,
				Payload: encrypt(t, currentPass),
				SenderAvatar: prefs.String("avatar_base64"),
			}
			b, _ := json.Marshal(m)
			req, _ := http.NewRequest("POST", supabaseURL+"/rest/v1/messages", bytes.NewBuffer(b))
			req.Header.Set("apikey", supabaseKey)
			req.Header.Set("Authorization", "Bearer "+supabaseKey)
			req.Header.Set("Content-Type", "application/json")
			(&http.Client{}).Do(req)
		}()
	})

	window.SetContent(container.NewBorder(
		container.NewHBox(menuBtn, widget.NewLabelWithStyle("MEOW CHAT", fyne.TextAlignLeading, fyne.TextStyle{Bold: true})),
		container.NewBorder(nil, nil, nil, sendBtn, msgInput),
		nil, nil, chatScroll,
	))
	window.ShowAndRun()
}
