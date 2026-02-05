# Aiogram + SQLAlchemy Python Telegram Bot Project Scaffold

A bash script for rapid deployment of a Python Telegram bot project. It automatically creates a virtual environment, installs dependencies, and sets up a modular layered architecture (database, routers, keyboards).

## What's Inside
- **Aiogram 3.x**: Modern asynchronous framework for Telegram bots.
- **SQLAlchemy + Aiosqlite**: Database interaction via ORM.
- **UI Manager**: A helper to update messages and minimize chat clutter.
- **FSM History**: Automatic transition history tracking for the universal "Back" button.

## Project Structure
```text
core/
├── database/     # Table models and session manager
├── keyboards/    # Inline keyboard builders
├── routers/      # Command and message handlers
└── utils/        # FSM states and BotManager logic
.env              # Configuration (token, db, admins)
.gitignore        # Git exclusion list
init.sh           # Deployment script
main.py           # Entry point
README.md         # Project documentation
requirements.txt  # Project dependencies list
```

## Installation and Run

### 1. Deploy the project
Run the following commands to set up the environment and project structure:
```bash
chmod +x init.sh
./init.sh
```

### 2. Configure environment
Edit the generated `.env` file with your credentials:
```env
BOT_TOKEN=your_token_here
DATABASE_URL=sqlite+aiosqlite:///db.sqlite3
ADMIN_ID=12345678
```

### 3. Run the bot
Activate the virtual environment and start the application:
```bash
source venv/bin/activate
python main.py
```
