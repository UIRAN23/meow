#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <fstream>
#include <iomanip>
#include <chrono>
#include <sys/stat.h>
#include <curl/curl.h>
#include <nlohmann/json.hpp>
#include <openssl/evp.h>
#include <openssl/sha.h>
#include <clocale>
#include <algorithm>
#include <set>
#include <unistd.h>
#include "httplib.h"

using namespace std;
using json = nlohmann::json;
const string VERSION = "5.0";

// --- НАСТРОЙКИ ---
const string SB_URL = "https://ilszhdmqxsoixcefeoqa.supabase.co/rest/v1/messages";
const string SB_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc";
const int PUA_START = 0xE000;

string my_pass, my_nick, my_room, cfg;
vector<pair<string, string>> chat_history; 
set<string> known_ids;
mutex mtx;

// --- КРИПТО (ТВОЙ КОД) ---
string aes_256(string text, string pass, bool enc) {
    unsigned char key[32], iv[16] = {0};
    SHA256((unsigned char*)pass.c_str(), pass.length(), key);
    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    int len, flen; unsigned char out[1024*1024*2]; // 2MB буфер для фото
    if(enc) {
        EVP_EncryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv);
        EVP_EncryptUpdate(ctx, out, &len, (unsigned char*)text.c_str(), text.length());
        EVP_EncryptFinal_ex(ctx, out + len, &flen);
    } else {
        EVP_DecryptInit_ex(ctx, EVP_aes_256_cbc(), NULL, key, iv);
        EVP_DecryptUpdate(ctx, out, &len, (unsigned char*)text.c_str(), text.length());
        if(EVP_DecryptFinal_ex(ctx, out + len, &flen) <= 0) { EVP_CIPHER_CTX_free(ctx); return "ERR_DECRYPT"; }
    }
    EVP_CIPHER_CTX_free(ctx);
    return string((char*)out, len + flen);
}

// --- ВСПОМОГАТЕЛЬНЫЕ ---
string from_z(string in) {
    string res = "";
    for (size_t i = 0; i < in.length(); ) {
        if ((unsigned char)in[i] == 0xEE) {
            int code = ((in[i+1] & 0x3F) << 6) | (in[i+2] & 0x3F);
            res += (char)(code); i += 3;
        } else if ((unsigned char)in[i] == 0xCC) { i += 2; } else { i++; }
    }
    return res;
}

string to_z(string in) {
    string res = "";
    for (unsigned char b : in) {
        int code = PUA_START + b;
        res += (char)(0xEE); res += (char)(0x80 | ((code >> 6) & 0x3F)); res += (char)(0x80 | (code & 0x3F));
        res += "\xCC\xA1";
    }
    return res;
}

size_t write_cb(void* ptr, size_t size, size_t nmemb, void* up) {
    ((string*)up)->append((char*)ptr, size * nmemb);
    return size * nmemb;
}

string request(string method, int limit, int offset, string body = "") {
    CURL* curl = curl_easy_init();
    string resp;
    if(curl) {
        struct curl_slist* h = NULL;
        h = curl_slist_append(h, ("apikey: " + SB_KEY).c_str());
        h = curl_slist_append(h, ("Authorization: Bearer " + SB_KEY).c_str());
        h = curl_slist_append(h, "Content-Type: application/json");
        string url = SB_URL + "?chat_key=eq." + my_room + "&order=id.desc&limit=" + to_string(limit) + "&offset=" + to_string(offset);
        if (method == "POST") { curl_easy_setopt(curl, CURLOPT_POST, 1L); curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.c_str()); }
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, h);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &resp);
        curl_easy_perform(curl); curl_easy_cleanup(curl);
    }
    return resp;
}

// --- ФОНОВОЕ ОБНОВЛЕНИЕ ---
void update_loop() {
    while(true) {
        string r = request("GET", 20, 0);
        if (!r.empty() && r[0] == '[') {
            auto data = json::parse(r);
            lock_guard<mutex> l(mtx);
            for (int i = data.size()-1; i >= 0; i--) {
                string id = to_string(data[i].value("id", 0));
                if (known_ids.find(id) == known_ids.end()) {
                    string snd = data[i].value("sender", "");
                    string payload = data[i].value("payload", "");
                    string decoded = aes_256(from_z(payload), my_pass, false);
                    chat_history.push_back({id, "[" + snd + "]: " + decoded});
                    known_ids.insert(id);
                }
            }
            if(chat_history.size() > 50) chat_history.erase(chat_history.begin(), chat_history.begin() + 10);
        }
        this_thread::sleep_for(chrono::seconds(3));
    }
}

// --- MAIN ---
int main() {
    cfg = string(getenv("HOME")) + "/.fntm/config.dat";
    ifstream fi(cfg);
    if(fi) { getline(fi, my_nick); getline(fi, my_pass); getline(fi, my_room); }
    else { cout << "Запусти консольную версию один раз для настройки!" << endl; return 1; }

    thread(update_loop).detach();

    httplib::Server svr;

    svr.Get("/", [](const httplib::Request&, httplib::Response& res) {
        string html = R"(
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Termux Web Chat</title>
            <style>
                body { font-family: -apple-system, sans-serif; background: #000; color: #eee; margin: 0; display: flex; flex-direction: column; height: 100vh; }
                #chat { flex: 1; overflow-y: auto; padding: 15px; display: flex; flex-direction: column; gap: 10px; }
                .msg { background: #222; padding: 10px; border-radius: 12px; max-width: 85%; align-self: flex-start; word-wrap: break-word; }
                .msg.me { align-self: flex-end; background: #007bff; }
                .msg b { color: #aaa; font-size: 0.8em; display: block; margin-bottom: 4px; }
                .msg img { max-width: 100%; border-radius: 8px; display: block; margin-top: 5px; cursor: pointer; }
                #input-bar { background: #111; padding: 10px; display: flex; gap: 10px; align-items: center; border-top: 1px solid #333; }
                input[type="text"] { flex: 1; background: #222; border: none; color: white; padding: 12px; border-radius: 20px; outline: none; }
                #file-btn { font-size: 20px; cursor: pointer; user-select: none; }
                button#send-btn { background: #007bff; color: white; border: none; padding: 10px 18px; border-radius: 20px; font-weight: bold; }
            </style>
        </head>
        <body>
            <div id="chat"></div>
            <div id="input-bar">
                <div id="file-btn">📷</div>
                <input type="file" id="fileInput" accept="image/*" style="display:none">
                <input type="text" id="msgInput" placeholder="Сообщение...">
                <button id="send-btn" onclick="sendMsg()">></button>
            </div>
            <script>
                const myNick = ")"; + my_nick + R"(";
                async function load() {
                    const r = await fetch('/get_messages');
                    const msgs = await r.json();
                    const chat = document.getElementById('chat');
                    const shouldScroll = chat.scrollTop + chat.offsetHeight >= chat.scrollHeight - 50;
                    chat.innerHTML = '';
                    msgs.forEach(m => {
                        let content = m.text;
                        if(content.startsWith('img:')) {
                            content = `<img src="data:image/png;base64,${content.substring(4)}" onclick="window.open(this.src)">`;
                        }
                        const isMe = m.sender === myNick ? 'me' : '';
                        chat.innerHTML += `<div class="msg ${isMe}"><b>${m.sender}</b>${content}</div>`;
                    });
                    if(shouldScroll) chat.scrollTop = chat.scrollHeight;
                }
                async function sendMsg() {
                    const input = document.getElementById('msgInput');
                    const text = input.value;
                    if(!text) return;
                    input.value = '';
                    await fetch('/send', { method: 'POST', body: text });
                    load();
                }
                document.getElementById('file-btn').onclick = () => document.getElementById('fileInput').click();
                document.getElementById('fileInput').onchange = async (e) => {
                    const file = e.target.files[0];
                    if(!file) return;
                    const reader = new FileReader();
                    reader.onload = async () => {
                        const base64 = reader.result.split(',')[1];
                        await fetch('/send', { method: 'POST', body: 'img:' + base64 });
                    };
                    reader.readAsDataURL(file);
                };
                document.getElementById('msgInput').onkeypress = (e) => { if(e.key === 'Enter') sendMsg(); };
                setInterval(load, 2000);
                load();
            </script>
        </body>
        </html>
        )";
        res.set_content(html, "text/html");
    });

    svr.Get("/get_messages", [](const httplib::Request&, httplib::Response& res) {
        json j = json::array();
        lock_guard<mutex> l(mtx);
        for (auto& p : chat_history) {
            size_t pos = p.second.find("]: ");
            if(pos != string::npos) {
                string s = p.second.substr(1, pos - 1);
                string t = p.second.substr(pos + 3);
                j.push_back({{"sender", s}, {"text", t}});
            }
        }
        res.set_content(j.dump(), "application/json");
    });

    svr.Post("/send", [](const httplib::Request& req, httplib::Response& res) {
        string msg = req.body;
        thread([msg](){
            string encrypted = to_z(aes_256(msg, my_pass, true));
            json j = {{"sender", my_nick}, {"payload", encrypted}, {"chat_key", my_room}};
            request("POST", 0, 0, j.dump());
        }).detach();
        res.set_content("ok", "text/plain");
    });

    cout << "Server started at http://localhost:8080" << endl;
    svr.listen("0.0.0.0", 8080);
    return 0;
}
