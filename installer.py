import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import sys
import os
import threading
from pathlib import Path

class InstallerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Установка Нейросети")
        self.root.geometry("400x350")
        self.root.resizable(False, False)
        
        # Styles
        style = ttk.Style()
        style.configure("TButton", padding=6, font=("Segoe UI", 10))
        style.configure("TLabel", font=("Segoe UI", 10))
        style.configure("Header.TLabel", font=("Segoe UI", 14, "bold"))
        
        # Header
        header = ttk.Label(root, text="Установка Нейросети", style="Header.TLabel")
        header.pack(pady=20)
        
        # Instructions
        self.status_label = ttk.Label(root, text="Нажмите 'Начать установку'", wraplength=350, justify="center")
        self.status_label.pack(pady=10)
        
        # Checkbox for shortcut
        self.shortcut_var = tk.BooleanVar(value=True)
        self.chk_shortcut = ttk.Checkbutton(root, text="Создать ярлык на рабочем столе", variable=self.shortcut_var)
        self.chk_shortcut.pack(pady=10)
        
        # Progress bar
        self.progress = ttk.Progressbar(root, orient="horizontal", length=300, mode="indeterminate")
        self.progress.pack(pady=20)
        
        # Button
        self.btn_install = ttk.Button(root, text="Начать установку", command=self.start_installation)
        self.btn_install.pack(pady=10)
        
        # Log area (hidden by default, can be added if needed, but keeping it simple)

    def start_installation(self):
        self.btn_install.config(state="disabled")
        self.chk_shortcut.config(state="disabled")
        self.progress.start(10)
        self.status_label.config(text="Инициализация...")
        
        thread = threading.Thread(target=self.run_installation)
        thread.start()

    def run_installation(self):
        try:
            # Force CWD to be the script's directory
            os.chdir(os.path.dirname(os.path.abspath(__file__)))

            # Step 1: Install requirements
            self.update_status("Установка библиотек (это может занять время)...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "pip"])
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])
            
            # Step 2: Train model (if needed)
            self.update_status("Обучение нейросети (первичная настройка)...")
            # Run train_model.py
            result = subprocess.run([sys.executable, "train_model.py"], capture_output=True, text=True)
            if result.returncode != 0:
                print(result.stderr)
                raise Exception("Ошибка при обучении модели. Проверьте консоль или логи.")

            # Step 3: Create shortcut
            if self.shortcut_var.get():
                self.update_status("Создание ярлыка...")
                self.create_shortcut()

            self.root.after(0, self.finish_success)
            
        except Exception as e:
            error_message = str(e)
            self.root.after(0, lambda: self.finish_error(error_message))

    def update_status(self, text):
        self.root.after(0, lambda: self.status_label.config(text=text))

    def create_shortcut(self):
        desktop = os.path.join(os.path.join(os.environ['USERPROFILE']), 'Desktop') 
        script_path = os.path.abspath("app.pyw")
        icon_path = os.path.abspath("data/icon.ico")
        working_dir = os.getcwd()
        
        if not os.path.exists(icon_path):
            icon_path = sys.executable # Fallback to python icon
            
        # Use PowerShell to create shortcut
        ps_command = f"$s=(New-Object -COM WScript.Shell).CreateShortcut('{desktop}\\Нейросеть Остеоартрит.lnk');" \
                     f"$s.TargetPath='pythonw.exe';" \
                     f"$s.Arguments='\"{script_path}\"';" \
                     f"$s.WorkingDirectory='{working_dir}';" \
                     f"$s.IconLocation='{icon_path}';" \
                     f"$s.Save()"
        
        subprocess.run(["powershell", "-Command", ps_command], check=True)

    def finish_success(self):
        self.progress.stop()
        self.progress.pack_forget()
        self.status_label.config(text="Установка успешно завершена!")
        messagebox.showinfo("Успех", "Программа установлена и готова к работе!")
        self.root.destroy()

    def finish_error(self, error_msg):
        self.progress.stop()
        self.btn_install.config(state="normal")
        self.status_label.config(text="Произошла ошибка!")
        messagebox.showerror("Ошибка", f"Не удалось установить:\n{error_msg}")

if __name__ == "__main__":
    root = tk.Tk()
    app = InstallerApp(root)
    root.mainloop()
