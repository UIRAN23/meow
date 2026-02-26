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
	"log"
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
	ID      int    `json:"id"`
	Sender  string `json:"sender"`
	Payload string `json:"payload"`
}

func fastDecrypt(cryptoText, key string) string {
	if len(cryptoText) < 16 { return cryptoText }
	fixedKey := make([]byte, 32); copy(fixedKey, key)
	ciphertext, _ := base64.StdEncoding.DecodeString(cryptoText)
	block, _ := aes.NewCipher(fixedKey)
	iv := ciphertext[:aes.BlockSize]
	stream := cipher.NewCFBDecrypter(block, iv)
	res := ciphertext[aes.BlockSize:]
	stream.XORKeyStream(res, res)
	return string(res)
}

func main() {
	// Отключаем софт-рендеринг, пробуем нативный
	os.Unsetenv("FYNE_RENDER") 
	
	myApp := app.NewWithID("com.itoryon.imperor.v30")
	window := myApp.NewWindow("Imperor v30")
	window.Resize(fyne.NewSize(500, 800))

	prefs := myApp.Preferences()
	var currentRoom, currentPass string
	var lastID int
	
	// Данные для списка
	var data []string
	messagesList := widget.NewList(
		func() int { return len(data) },
		func() fyne.CanvasObject { return widget.NewLabel("Template") },
		func(id widget.ListItemID, o fyne.CanvasObject) {
			o.(*widget.Label).SetText(data[id])
		},
	)

	go func() {
		for {
			if currentRoom == "" {
				time.Sleep(time.Second)
				continue
			}

			url := fmt.Sprintf("%s/rest/v1/messages?chat_key=eq.%s&id=gt.%d&order=id.asc", supabaseURL, currentRoom, lastID)
			req, _ := http.NewRequest("GET", url, nil)
			req.Header.Set("apikey", supabaseKey)
			req.Header.Set("Authorization", "Bearer "+supabaseKey)

			resp, err := (&http.Client{Timeout: 10 * time.Second}).Do(req)
			if err != nil {
				log.Println("CRITICAL ERROR:", err)
				time.Sleep(5 * time.Second)
				continue
			}

			if resp.StatusCode != 200 {
				log.Println("SUPABASE ERROR:", resp.StatusCode)
				resp.Body.Close()
				time.Sleep(5 * time.Second)
				continue
			}

			var msgs []Message
			json.NewDecoder(resp.Body).Decode(&msgs)
			resp.Body.Close()

			if len(msgs) > 0 {
				log.Printf("LOADED %d MESSAGES", len(msgs))
				for _, m := range msgs {
					lastID = m.ID
					decrypted := fastDecrypt(m.Payload, currentPass)
					data = append(data, m.Sender+": "+decrypted)
				}
				messagesList.Refresh()
				messagesList.ScrollToBottom()
			}
			time.Sleep(3 * time.Second)
		}
	}()

	// Интерфейс
	msgInput := widget.NewEntry()
	sendBtn := widget.NewButtonWithIcon("", theme.MailSendIcon(), func() {
		if msgInput.Text == "" || currentRoom == "" { return }
		// Отправка (упрощено для теста)
		go func() {
			log.Println("SENDING MESSAGE...")
		}()
		msgInput.SetText("")
	})

	menuBtn := widget.NewButton("MENU", func() {
		idEntry := widget.NewEntry()
		idEntry.SetPlaceHolder("Room ID")
		passEntry := widget.NewPasswordEntry()
		passEntry.SetPlaceHolder("Key")

		dialog.ShowForm("Connect", "Join", "Cancel", []*widget.FormItem{
			{Text: "ID", Widget: idEntry},
			{Text: "Pass", Widget: passEntry},
		}, func(ok bool) {
			if ok {
				currentRoom = idEntry.Text
				currentPass = passEntry.Text
				data = nil // Чистим чат
				lastID = 0
				messagesList.Refresh()
				log.Println("JOINED ROOM:", currentRoom)
			}
		}, window)
	})

	window.SetContent(container.NewBorder(
		container.NewHBox(menuBtn, canvas.NewText(" Imperor Chat", theme.PrimaryColor())),
		container.NewBorder(nil, nil, nil, sendBtn, msgInput),
		nil, nil,
		messagesList,
	))

	log.Println("APP STARTED SUCCESSFULLY")
	window.ShowAndRun()
}
