#!/usr/bin/env python3
"""Yeni bir oyun modunun iskeletini üretir ve kayıtlarını yapar.

Bir mod eklemek 11 ayrı yere dokunmayı gerektiriyor; unutulan her kayıt
çalışma anında hataya dönüşüyordu. Bu betik hepsini bir kerede kurar:

    python backend/scripts/new_mode.py son_dakika "Son Dakika"

Ürettikleri:
  * backend/app/realtime/modes/<id>.py        mod motoru iskeleti
  * backend/tests/test_<id>_mode.py           motorun temel testi
  * lib/features/games/<camel>/<id>_screen.dart  ekran iskeleti
Kaydettikleri:
  * protocol.py GameMode
  * hub.py MODE_ENGINES
  * mode_service.py etiket ve sürüm eşiği
  * game_mode.dart enum girdisi

Kayıt bütünlüğü testleri (tests/test_mode_registry.py) her şeyin yerine
oturduğunu doğrular; betikten sonra `pytest` çalıştırmak yeterli.

Var olan dosyanın üzerine yazmaz; ikinci kez çalıştırmak güvenlidir.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def camel(mode_id: str) -> str:
    head, *rest = mode_id.split("_")
    return head + "".join(part.capitalize() for part in rest)


def pascal(mode_id: str) -> str:
    return "".join(part.capitalize() for part in mode_id.split("_"))


def write(path: pathlib.Path, body: str) -> bool:
    if path.exists():
        print(f"  atlandi (zaten var): {path.relative_to(ROOT)}")
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    print(f"  olusturuldu: {path.relative_to(ROOT)}")
    return True


def patch(path: pathlib.Path, anchor: str, addition: str, marker: str) -> None:
    source = path.read_text()
    if marker in source:
        print(f"  atlandi (zaten kayitli): {path.relative_to(ROOT)}")
        return
    if anchor not in source:
        print(f"  ! capa bulunamadi, elle ekleyin: {path.relative_to(ROOT)}")
        return
    path.write_text(source.replace(anchor, addition, 1))
    print(f"  guncellendi: {path.relative_to(ROOT)}")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    mode_id, title = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"[a-z][a-z0-9_]*", mode_id):
        print("Mod kimligi kucuk harf ve alt cizgi olmali, orn: son_dakika")
        return 2

    const = mode_id.upper()
    klass = pascal(mode_id) + "Mode"
    dart_enum = camel(mode_id)

    print(f"▶ {title} ({mode_id})")

    # --- backend motoru ---
    write(ROOT / f"backend/app/realtime/modes/{mode_id}.py", f'''"""{title}.

TODO: modun kurallarini burada anlat — tur akisi, puanlama, bitis kosulu.
"""

import asyncio

from app.realtime.modes.base import BaseMode
from app.realtime.protocol import ErrorCode, GameMode, ServerMessage, error


class {klass}(BaseMode):
    mode_id = GameMode.{const}

    def __init__(self, room) -> None:
        super().__init__(room)
        self.phase: str = "idle"
        self.round: int = 0

    async def start(self) -> None:
        await self.room.broadcast({{
            "type": ServerMessage.START,
            "mode": self.mode_id,
            "payload": self.state(),
        }})
        self.spawn(self._run())

    async def _run(self) -> None:
        self.phase = "playing"
        await self.push_state()
        # TODO: tur dongusunu yaz.
        await asyncio.sleep(0)

    async def handle_action(self, player, payload: dict) -> None:
        action = payload.get("action")
        if action == "answer":
            await self._handle_answer(player, payload)

    async def _handle_answer(self, player, payload: dict) -> None:
        if self.phase != "playing":
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Su an cevap asamasi degil."))
            return
        # TODO: cevabi dogrula ve puanla.

    def state(self) -> dict:
        return {{
            "phase": self.phase,
            "round": self.round,
            "scores": {{p.slot: p.score for p in self.room.players}},
        }}
''')

    # --- backend testi ---
    write(ROOT / f"backend/tests/test_{mode_id}_mode.py", f'''"""{title} motorunun temel davranisi."""

import pytest

from app.realtime.modes.{mode_id} import {klass}
from app.realtime.protocol import GameMode
from tests.fakes import FakeRoom


def test_motor_kendi_modunu_bildiriyor():
    assert {klass}.mode_id == GameMode.{const}


@pytest.mark.asyncio
async def test_baslangic_durumu_yayinlanir():
    room = FakeRoom()
    mode = {klass}(room)
    await mode.start()
    assert any(m.get("type") == "start" for m in room.players[0].socket.sent)


# TODO: modun kendi kurallarina dair testleri buraya ekle.
''')

    # --- flutter ekrani ---
    write(ROOT / f"lib/features/games/{mode_id}/{mode_id}_screen.dart", f'''import 'dart:async';

import 'package:flutter/material.dart';

import 'package:footttball/data/models/game_mode.dart';
import 'package:footttball/data/models/room_models.dart';
import 'package:footttball/data/services/game_socket.dart';
import 'package:footttball/features/modes/mode_select_screen.dart';
import 'package:footttball/shared/widgets/app_background.dart';
import 'package:footttball/shared/widgets/connection_banner.dart';
import 'package:footttball/shared/widgets/game_dialogs.dart';

/// {title} modu.
///
/// TODO: modun akisini burada anlat.
class {pascal(mode_id)}Screen extends StatefulWidget {{
  const {pascal(mode_id)}Screen({{super.key}});

  @override
  State<{pascal(mode_id)}Screen> createState() => _{pascal(mode_id)}ScreenState();
}}

class _{pascal(mode_id)}ScreenState extends State<{pascal(mode_id)}Screen> {{
  final _socket = GameSocket.instance;
  StreamSubscription<SocketEvent>? _subscription;
  Map<String, dynamic> _state = const {{}};
  bool _gameOver = false;

  @override
  void initState() {{
    super.initState();
    _state = _socket.lastState;
    _subscription = _socket.events.listen(_onEvent);
  }}

  @override
  void dispose() {{
    _subscription?.cancel();
    super.dispose();
  }}

  void _onEvent(SocketEvent event) {{
    if (!mounted) return;
    switch (event.type) {{
      case 'start':
      case 'state':
        setState(() => _state = event.payload);
        break;
      case 'over':
        _gameOver = true;
        break;
      case 'opponent_left':
        if (!_gameOver) {{
          _gameOver = true;
          GameDialogs.showDisconnected(context, onExit: _exitToMenu);
        }}
        break;
    }}
  }}

  void _exitToMenu() {{
    _socket.leave();
    _socket.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ModeSelectScreen()),
      (route) => false,
    );
  }}

  @override
  Widget build(BuildContext context) {{
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {{
        if (!didPop) _exitToMenu();
      }},
      child: Scaffold(
        body: Stack(
          children: [
            GameBackground(accent: GameMode.{dart_enum}.colors.first),
            SafeArea(
              child: Center(
                // TODO: oyun arayuzunu yaz.
                child: Text(
                  '{title}\\n${{_state['phase'] ?? '...'}}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            const Align(
                alignment: Alignment.topCenter, child: ConnectionBanner()),
          ],
        ),
      ),
    );
  }}
}}
''')

    # --- kayitlar ---
    patch(ROOT / "backend/app/realtime/protocol.py",
          "    CATEGORY_RACE = \"category_race\"",
          f"    CATEGORY_RACE = \"category_race\"\n    {const} = \"{mode_id}\"",
          f'{const} = "{mode_id}"')

    patch(ROOT / "backend/app/realtime/hub.py",
          "from app.realtime.modes.category_race import CategoryRaceMode",
          f"from app.realtime.modes.category_race import CategoryRaceMode\n"
          f"from app.realtime.modes.{mode_id} import {klass}",
          f"import {klass}")

    patch(ROOT / "backend/app/realtime/hub.py",
          "    GameMode.CATEGORY_RACE: CategoryRaceMode,",
          f"    GameMode.CATEGORY_RACE: CategoryRaceMode,\n    GameMode.{const}: {klass},",
          f"GameMode.{const}: {klass}")

    patch(ROOT / "backend/app/services/mode_service.py",
          '    GameMode.CATEGORY_RACE: "1.0.0",',
          f'    GameMode.CATEGORY_RACE: "1.0.0",\n    GameMode.{const}: "1.0.0",',
          f"GameMode.{const}: \"1.0.0\"")

    patch(ROOT / "backend/app/services/mode_service.py",
          '    GameMode.CATEGORY_RACE: "Kategori Yarışı",',
          f'    GameMode.CATEGORY_RACE: "Kategori Yarışı",\n    GameMode.{const}: "{title}",',
          f'GameMode.{const}: "{title}"')

    patch(ROOT / "lib/data/models/game_mode.dart",
          "  );\n\n  const GameMode({",
          f"""  ),
  {dart_enum}(
    id: '{mode_id}',
    title: '{title}',
    tagline: 'TODO: kisa aciklama',
    description: 'TODO: modun nasil oynandigini anlat.',
    icon: Icons.sports_soccer_rounded,
    colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
  );

  const GameMode({{""",
          f"id: '{mode_id}'")

    print()
    print("Kalan elle isler:")
    print("  1. lib/features/lobby/vs_screen.dart      -> ekrani yonlendir")
    print("  2. lib/features/lobby/waiting_room_screen.dart -> kural ozeti")
    print("  3. lib/features/lobby/create_room_screen.dart  -> oda ayarlari")
    print("  4. test/responsive_test.dart              -> ekran boyutu testi")
    print("  (1 ve 2 exhaustive switch oldugu icin zaten derleme hatasi verir)")
    print()
    print("Dogrulama: cd backend && pytest tests/test_mode_registry.py -q")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
