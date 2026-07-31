# 推廣影片

56 秒、1280×720，全程在 docker 裡做（`tools/promo-record.sh` 擷取、`tools/make_promo.sh` 合成），
不開剪輯軟體、可重跑。成品只留本機 `dist-all/`：

| 檔案 | 用途 |
|---|---|
| `maniac-mansion-cht-promo.mp4` | 完整推廣片（含配樂） |
| `maniac-cht.gif` | README 用的靜音 GIF（8 秒、480 寬） |

## 素材都是實機的

* **畫面**：`x11grab` 錄自編 ScummVM 的真實遊玩（1988 v2 中文版），以及 Deluxe 的實機截圖。
  放大一律用 `flags=neighbor`（最近鄰），保持點陣銳利。
* **配樂**：**Deluxe 遊戲內建的音樂，用 `SDL_AUDIODRIVER=disk` 從引擎直接錄下來**，
  不是自己合成的逼近音色。

## MT-32 對這兩款都不適用（實測 + 讀原始碼）

原本要用 MT-32 音源，查證後確定走不通，兩邊各有各的原因：

**1988 原版（SCUMM v1/v2）：引擎裡根本沒有 MIDI 路徑。** `engines/scumm/scumm.cpp` 的
`setupMusic()` 選音樂引擎時寫得很直接：

```cpp
} else if (_game.version <= 2) {
    _musicEngine = new Player_V2(this, _mixer, MidiDriver::getMusicType(dev) != MT_PCSPK);
```

`Player_V2` 是 PC 喇叭／PCjr 的方波播放器。`--music-driver=` 對它唯一的作用是決定跑 PCjr 還是
PC speaker 模式——**MT-32 這個選項對 v1/v2 不存在**。實測 `--music-driver=mt32`（有放
`MT32_CONTROL.ROM` / `MT32_PCM.ROM`）與 `adlib` 兩次擷取的音量統計完全一樣。

**Deluxe（AGS）：音訊是數位檔，不是 MIDI。** 同一段流程各錄一次 `mt32` 與 `auto`，
逐秒 RMS **差 0.00 dB**——完全相同的波形，代表音訊直接播放、沒有經過任何 MIDI 合成器，
所以 MT-32 ROM 放了也不會被用到。

## 原版幾乎沒有可用的配樂

第一性檢查（`ffmpeg volumedetect` / `silencedetect`）的結果：

| 來源 | 結果 |
|---|---|
| v2 標題畫面（adlib / pcjr / pcspk 各 65 秒） | `mean_volume: -91.0 dB` = 數位純靜音 |
| C64 版標題（`--music-driver=C64`，130 秒） | 同樣 -91.0 dB |
| v2 遊戲中（115 秒） | 只有兩個約 70 ms 的音效點擊，其餘靜音 |
| Deluxe 片頭導覽 + 開場 | 前 116 秒靜音，之後是**語音**（每 3.5 秒一段、中間數位靜音） |
| **Deluxe 進遊戲之後** | **連續 -18 dB 穩定訊號，頻譜有節奏性與豐富泛音 = 音樂** ✅ |

所以配樂取自最後這一段（`ffmpeg -ss 213 -t 34`），加淡入淡出後循環。
判斷方式是頻譜與逐秒 RMS，不是憑耳朵猜（`rulebook/93` 鐵則 2）。

## 公開之前要先決定的事

`rulebook/93` 的但書：用原版音樂管的是「品質真實」，跟「能不能公開散布」是兩回事。
這支片的配樂是 **Maniac Mansion Deluxe 的遊戲音樂（Lucasfan Games）**，畫面是
**Maniac Mansion 的美術（原權利人）**。

* 本機保存 / 內部 demo：沒問題，產物 gitignore 不入庫。
* **上 YouTube 或放進公開 repo：等於散布他人著作**，要先確認。目前只留在 `dist-all/`，沒有上傳。
