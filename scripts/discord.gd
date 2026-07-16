extends Node
## Discord Rich Presence, кроссплатформенно:
##  - Windows: именованный пайп \\.\pipe\discord-ipc-N (FileAccess)
##  - Linux:   unix-сокет $XDG_RUNTIME_DIR/discord-ipc-N через мост python3
##             (Godot не открывает unix-сокеты; мост гоняет байты stdin<->сокет)
## Вся работа с каналом — в фоновом потоке (запись может блокироваться).

const APP_ID := "1525892578287947947"
const UPDATE_INTERVAL := 5.0
const WORKER_TICK_MS := 300

# python3-мост для Linux: ищет сокет Discord (включая flatpak/snap) и шлюзует байты
const LINUX_BRIDGE := """
import socket, sys, os, threading
def find():
    dirs = []
    x = os.environ.get('XDG_RUNTIME_DIR')
    if x:
        dirs += [x, x + '/app/com.discordapp.Discord', x + '/snap.discord']
    dirs += ['/run/user/%d' % os.getuid(), '/tmp']
    for d in dirs:
        for i in range(10):
            p = '%s/discord-ipc-%d' % (d, i)
            if os.path.exists(p):
                return p
    return None
p = find()
if not p:
    sys.exit(1)
s = socket.socket(socket.AF_UNIX)
s.connect(p)
def up():
    while True:
        d = s.recv(4096)
        if not d:
            os._exit(0)
        os.write(1, d)
threading.Thread(target=up, daemon=True).start()
while True:
    d = os.read(0, 4096)
    if not d:
        break
    s.sendall(d)
"""

var _thread: Thread = null
var _mutex := Mutex.new()
var _quit := false
var _enabled := true
var _pending: Dictionary = {}
var _update := 0.0
var _start_ts := 0
var _bridge_pid := -1


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _start_ts = int(Time.get_unix_time_from_system())
    if OS.get_name() in ["Windows", "Linux"]:
        _thread = Thread.new()
        _thread.start(_worker)


func _exit_tree() -> void:
    if _thread != null:
        _mutex.lock()
        _quit = true
        _mutex.unlock()
        # мост убиваем сразу — это разблокирует чтение в воркере
        _mutex.lock()
        var pid := _bridge_pid
        _mutex.unlock()
        if pid > 0:
            OS.kill(pid)
        _thread.wait_to_finish()


func _process(delta: float) -> void:
    if _thread == null:
        return
    _update -= delta
    if _update > 0:
        return
    _update = UPDATE_INTERVAL

    # строки собираем на главном потоке (tr/Net из воркера трогать нельзя)
    var details := tr("В главном меню")
    var state := ""
    if Net.game != null:
        match Net.game_mode:
            "story":
                details = tr("Сюжет — Глава %d") % Net.campaign_chapter
            "pvp":
                details = tr("ПвП — арена с руинами, до 10 убийств")
            _:
                details = tr("Волны — волна %d") % maxi(Net.game.wave, 1)
        state = tr("В отряде: %d") % Net.players.size() if Net.players.size() > 1 else tr("В одиночку")

    _mutex.lock()
    _enabled = Settings.discord_enabled
    _pending = {
        "cmd": "SET_ACTIVITY",
        "args": {
            "pid": OS.get_process_id(),
            "activity": {
                "details": details,
                "state": state,
                "timestamps": {"start": _start_ts},
            },
        },
        "nonce": str(Time.get_ticks_msec()),
    }
    _mutex.unlock()


# ============================ фоновый поток ============================
func _worker() -> void:
    var pipe: FileAccess = null
    var sent := ""
    var retry_at := 0

    while true:
        OS.delay_msec(WORKER_TICK_MS)

        _mutex.lock()
        var quit := _quit
        var enabled := _enabled
        var pending := _pending.duplicate(true)
        _mutex.unlock()

        if quit:
            _close_ipc(pipe)
            break

        if not enabled or pending.is_empty():
            if pipe != null:
                _close_ipc(pipe)
                pipe = null
            sent = ""
            continue

        var now := Time.get_ticks_msec()
        if pipe == null:
            if now < retry_at:
                continue
            retry_at = now + 15000
            pipe = _open_ipc()
            if pipe != null:
                if _frame(pipe, 0, {"v": 1, "client_id": APP_ID}) and _read_frame(pipe):
                    sent = ""
                else:
                    _close_ipc(pipe)
                    pipe = null
            if pipe == null:
                continue

        var key := JSON.stringify(pending.args)
        if key != sent:
            if _frame(pipe, 1, pending) and _read_frame(pipe):
                sent = key
            else:
                _close_ipc(pipe)
                pipe = null


## Открывает канал к Discord под текущую ОС (вызывается из воркера).
func _open_ipc() -> FileAccess:
    if OS.get_name() == "Windows":
        for i in 10:
            var f := FileAccess.open("\\\\.\\pipe\\discord-ipc-%d" % i, FileAccess.READ_WRITE)
            if f != null:
                return f
        return null
    # Linux: мост python3 <-> unix-сокет
    var info := OS.execute_with_pipe("python3", ["-c", LINUX_BRIDGE])
    if info.is_empty():
        return null
    _mutex.lock()
    _bridge_pid = info.get("pid", -1)
    _mutex.unlock()
    var stdio: FileAccess = info.get("stdio")
    if stdio == null:
        return null
    # мосту нужно мгновение найти сокет; если сокета нет — процесс умрёт,
    # и первая же запись/чтение вернёт ошибку
    OS.delay_msec(200)
    return stdio


func _close_ipc(pipe: FileAccess) -> void:
    if pipe != null:
        pipe.close()
    _mutex.lock()
    var pid := _bridge_pid
    _bridge_pid = -1
    _mutex.unlock()
    if pid > 0:
        OS.kill(pid)


func _frame(pipe: FileAccess, op: int, payload: Dictionary) -> bool:
    var data := JSON.stringify(payload).to_utf8_buffer()
    var buf := PackedByteArray()
    buf.resize(8)
    buf.encode_u32(0, op)
    buf.encode_u32(4, data.size())
    buf.append_array(data)

    pipe.store_buffer(buf)
    pipe.flush()
    return pipe.get_error() == OK


func _read_frame(pipe: FileAccess) -> bool:
    var header := pipe.get_buffer(8)
    if header.size() < 8 or pipe.get_error() != OK:
        return false

    var length := header.decode_u32(4)
    if length > 0 and length < 65536:
        var body := pipe.get_buffer(length)
        if body.size() < length or pipe.get_error() != OK:
            return false

    return true
