#!/bin/bash

PROJECT_DIR=$(pwd)
VENV_PATH="$PROJECT_DIR/venv"

echo "Creating Telegram bot project scaffold..."

python3 -m venv "$VENV_PATH"
source "$VENV_PATH/bin/activate"

pip install --upgrade pip > /dev/null
pip install aiogram python-dotenv sqlalchemy aiosqlite > /dev/null

echo "aiogram
python-dotenv
sqlalchemy
aiosqlite" > "$PROJECT_DIR/requirements.txt"

mkdir -p "$PROJECT_DIR/database"
mkdir -p "$PROJECT_DIR/core/"{keyboards,routers,utils}

# --- Database Models ---
cat <<'EOF' > "$PROJECT_DIR/database/models.py"
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import BigInteger, String
from typing import Optional

class Base(DeclarativeBase): pass

class User(Base):
    __tablename__ = "users"
    user_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_name: Mapped[Optional[str]] = mapped_column(String(32))
    full_name: Mapped[Optional[str]] = mapped_column(String(128))
EOF

# --- Database Manager ---
cat <<'EOF' > "$PROJECT_DIR/database/db_manager.py"
from typing import List, Optional, Sequence
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncEngine, AsyncSession
from database.models import Base, User

class Database:
    def __init__(self, url: str) -> None:
        self.engine: AsyncEngine = create_async_engine(url)
        self.session_maker: async_sessionmaker[AsyncSession] = async_sessionmaker(self.engine, expire_on_commit=False)

    async def create_all(self) -> None:
        async with self.engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    async def add_user(self, user_id: int, user_name: Optional[str] = None, full_name: Optional[str] = None) -> None:
        async with self.session_maker() as session:
            user: Optional[User] = await session.scalar(select(User).where(User.user_id == user_id))
            if not user:
                session.add(User(user_id=user_id, user_name=user_name, full_name=full_name))
                await session.commit()

    async def get_all_users(self) -> Sequence[User]:
        async with self.session_maker() as session:
            result = await session.execute(select(User))
            return result.scalars().all()

    async def get_all_user_ids(self) -> List[int]:
        async with self.session_maker() as session:
            result = await session.execute(select(User.user_id))
            return [row[0] for row in result.all()]
EOF

# --- States ---
cat <<'EOF' > "$PROJECT_DIR/core/utils/states.py"
from aiogram.fsm.state import StatesGroup, State

class AdminState(StatesGroup):
    menu: State = State()
    broadcast: State = State()

class UserState(StatesGroup):
    main: State = State()
EOF

# --- Keyboards ---
cat <<'EOF' > "$PROJECT_DIR/core/keyboards/builders.py"
from aiogram.types import InlineKeyboardMarkup
from aiogram.utils.keyboard import InlineKeyboardBuilder

def admin_menu_kb() -> InlineKeyboardMarkup:
    builder: InlineKeyboardBuilder = InlineKeyboardBuilder()
    builder.button(text="📢 Broadcast", callback_data="admin_broadcast")
    builder.button(text="📋 Users List", callback_data="admin_users")
    builder.button(text="🚪 Exit", callback_data="admin_exit")
    return builder.adjust(1).as_markup()

def user_main_kb() -> InlineKeyboardMarkup:
    builder: InlineKeyboardBuilder = InlineKeyboardBuilder()
    builder.button(text="👤 My Profile", callback_data="user_profile")
    return builder.as_markup()

def back_kb(callback: str = "admin_back") -> InlineKeyboardMarkup:
    builder: InlineKeyboardBuilder = InlineKeyboardBuilder()
    builder.button(text="⬅️ Back", callback_data=callback)
    return builder.as_markup()
EOF

# --- UI Config ---
cat <<'EOF' > "$PROJECT_DIR/core/utils/ui_config.py"
from typing import Dict, Tuple, Optional
from aiogram.types import InlineKeyboardMarkup
from core.keyboards.builders import admin_menu_kb, user_main_kb

# Централизованное управление интерфейсом
UI_SCREENS: Dict[str, Tuple[str, Optional[InlineKeyboardMarkup]]] = {
    "AdminState:menu": ("🛠 Admin Panel", admin_menu_kb()),
    "UserState:main": ("🏠 Main Menu", user_main_kb()),
}

DEFAULT_SCREEN = ("Welcome to Main Menu", user_main_kb())
EOF

# --- Bot Manager ---
cat <<'EOF' > "$PROJECT_DIR/core/utils/bot_manager.py"
import asyncio
from typing import Union, Optional, List, Dict
from aiogram import Bot
from aiogram.types import Message, CallbackQuery, InlineKeyboardMarkup
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State
from aiogram.exceptions import TelegramBadRequest
from core.utils.ui_config import UI_SCREENS, DEFAULT_SCREEN

class BotManager:
    def __init__(self, bot: Bot) -> None:
        self.bot: Bot = bot

    async def update_ui(self, 
                        event: Union[Message, CallbackQuery], 
                        text: str, 
                        state: FSMContext, 
                        kb: Optional[InlineKeyboardMarkup] = None, 
                        new_state: Optional[State] = None) -> None:
        data: Dict = await state.get_data()
        history: List[str] = data.get("history", [])
        curr: Optional[str] = await state.get_state()
        
        if curr and (not history or history[-1] != curr):
            history.append(curr)
        
        await state.update_data(history=history)
        if new_state: 
            await state.set_state(new_state)

        try:
            if isinstance(event, CallbackQuery):
                await event.message.edit_text(text, reply_markup=kb)
            else:
                await event.answer(text, reply_markup=kb)
                try: await event.delete()
                except: pass
        except TelegramBadRequest:
            target: Message = event.message if isinstance(event, CallbackQuery) else event
            await target.answer(text, reply_markup=kb)

    async def render_by_state(self, event: Union[Message, CallbackQuery], state: FSMContext) -> None:
        curr_state: Optional[str] = await state.get_state()
        text, kb = UI_SCREENS.get(curr_state, DEFAULT_SCREEN)
        await self.update_ui(event, text, state, kb=kb)

    async def broadcast(self, user_ids: List[int], text: str) -> int:
        count: int = 0
        for uid in user_ids:
            try:
                await self.bot.send_message(uid, text)
                count += 1
                await asyncio.sleep(0.05)
            except: continue
        return count
EOF

# --- Routers Init ---
cat <<'EOF' > "$PROJECT_DIR/core/routers/__init__.py"
import pkgutil
import importlib
from typing import List
from aiogram import Router

def get_all_routers() -> List[Router]:
    routers: List[Router] = []
    for _, name, _ in pkgutil.walk_packages(__path__):
        mod = importlib.import_module(f"{__name__}.{name}")
        if hasattr(mod, "router") and isinstance(mod.router, Router):
            routers.append(mod.router)
    return routers
EOF

# --- Admin Router ---
cat <<'EOF' > "$PROJECT_DIR/core/routers/admin.py"
import os
from typing import Optional, List
from aiogram import Router, F
from aiogram.types import Message, CallbackQuery
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from core.utils.states import AdminState
from core.utils.bot_manager import BotManager
from database.db_manager import Database
from database.models import User
from core.keyboards.builders import admin_menu_kb, back_kb

router: Router = Router()

@router.message(Command("admin"))
async def open_admin(message: Message, state: FSMContext, manager: BotManager) -> None:
    admins: List[str] = os.getenv("ADMIN_ID", "").split(",")
    if str(message.from_user.id) not in admins: return
    await manager.update_ui(message, "🛠 Admin Panel", state, kb=admin_menu_kb(), new_state=AdminState.menu)

@router.callback_query(F.data == "admin_users")
async def show_users(call: CallbackQuery, state: FSMContext, db: Database, manager: BotManager) -> None:
    users: List[User] = await db.get_all_users()
    text: str = "📋 Users List:\n\n" + "\n".join([f"{u.user_id} | @{u.user_name}" for u in users]) if users else "Database is empty."
    await manager.update_ui(call, text, state, kb=back_kb())

@router.callback_query(F.data == "admin_broadcast")
async def start_broadcast(call: CallbackQuery, state: FSMContext, manager: BotManager) -> None:
    await manager.update_ui(call, "📝 Send me the message for broadcast:", state, kb=back_kb(), new_state=AdminState.broadcast)

@router.message(AdminState.broadcast)
async def process_broadcast(message: Message, state: FSMContext, db: Database, manager: BotManager) -> None:
    uids = await db.get_all_user_ids()
    sent_count = await manager.broadcast(uids, message.text)
    await manager.update_ui(message, f"✅ Broadcast finished!\nSent to: {sent_count} users.", state, kb=admin_menu_kb(), new_state=AdminState.menu)

@router.callback_query(F.data == "admin_back")
async def go_back(call: CallbackQuery, state: FSMContext, manager: BotManager) -> None:
    data: dict = await state.get_data()
    history: List[str] = data.get("history", [])
    if history:
        prev: str = history.pop()
        await state.update_data(history=history)
        await state.set_state(prev)
        await manager.render_by_state(call, state)

@router.callback_query(F.data == "admin_exit")
async def exit_admin(call: CallbackQuery, state: FSMContext) -> None:
    await state.clear()
    await call.message.edit_text("👋 Session terminated.")
EOF

# --- Start Router ---
cat << 'EOF' > "$PROJECT_DIR/core/routers/start.py"
from aiogram import Router, F
from aiogram.types import Message
from database.db_manager import Database

router: Router = Router()

@router.message(F.text == "/start")
async def start_h(message: Message, db: Database) -> None:
    await db.add_user(message.from_user.id, message.from_user.username, message.from_user.full_name)
    await message.answer("Registered!")
EOF

# --- Main Entry Point ---
cat <<'EOF' > "$PROJECT_DIR/main.py"
import asyncio
import os
import logging
from dotenv import load_dotenv
from aiogram import Bot, Dispatcher
from core.routers import get_all_routers
from database.db_manager import Database
from core.utils.bot_manager import BotManager

async def main() -> None:
    load_dotenv()
    logging.basicConfig(level=logging.INFO)
    db: Database = Database(os.getenv("DATABASE_URL"))
    await db.create_all()
    bot = Bot(token=os.getenv("BOT_TOKEN"))
    manager = BotManager(bot)
    dp = Dispatcher()
    dp.include_routers(*get_all_routers())
    await bot.delete_webhook(drop_pending_updates=True)
    await dp.start_polling(bot, manager=manager, db=db)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
EOF

# --- Env & Gitignore ---
echo "BOT_TOKEN='your_token'
DATABASE_URL=sqlite+aiosqlite:///db.sqlite3
ADMIN_ID=12345678" > "$PROJECT_DIR/.env"

cat <<'EOF' > "$PROJECT_DIR/.gitignore"
venv/
.env
__pycache__/
*.db
*.sqlite3
*.pyc
.DS_Store
EOF

touch "$PROJECT_DIR/core/__init__.py" "$PROJECT_DIR/database/__init__.py" \
      "$PROJECT_DIR/core/keyboards/__init__.py" "$PROJECT_DIR/core/utils/__init__.py" \
      "$PROJECT_DIR/README.md"

echo "Scaffold created successfully!"