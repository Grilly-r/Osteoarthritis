import tkinter as tk
from tkinter import ttk, messagebox
import threading
import sys
import os

# --- Глобальные переменные для "тяжелых" модулей ---
torch = None
nn = None
transforms = None
models = None
datasets = None
Image = None
ImageTk = None
Path = None

def load_heavy_modules():
    global torch, nn, transforms, models, datasets, Image, ImageTk, Path
    import torch
    import torch.nn as nn
    from torchvision import transforms, models, datasets
    from PIL import Image, ImageTk
    from pathlib import Path

# --- Логика нейросети (будет доступна после загрузки модулей) ---
def get_transform():
    return transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.Grayscale(num_output_channels=3),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5])
    ])

def load_model_and_classes():
    data_dir = Path("data")
    if not data_dir.exists():
        data_dir.mkdir()
    
    classes = ["healthy", "early", "severe"]
    try:
        ds = datasets.ImageFolder(root=str(data_dir))
        if ds.classes:
            classes = ds.classes
    except:
        pass

    model = models.mobilenet_v2(pretrained=False)
    model.classifier[1] = nn.Linear(1280, len(classes))
    
    model_path = Path("models/mobilenet_v2_osteoarthritis.pt")
    if model_path.exists():
        state = torch.load(model_path, map_location="cpu")
        model.load_state_dict(state)
    
    model.eval()
    return model, classes

def classify_image(model, classes, image_path):
    transform = get_transform()
    img = Image.open(str(image_path)).convert("RGB")
    x = transform(img).unsqueeze(0)
    with torch.no_grad():
        y = model(x)
        probs = torch.softmax(y, dim=1)[0]
    max_prob, idx = torch.max(probs, dim=0)
    max_prob_value = float(max_prob.item())
    
    # Сниженный порог, чтобы реже ошибаться на настоящих коленях
    if max_prob_value < 0.60:
        return "не кость", max_prob_value
    
    label = classes[int(idx.item())]
    return label, max_prob_value

# --- Основное приложение ---
class MainApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Анализ снимков: Остеоартрит")
        self.root.geometry("500x650")
        self.root.configure(bg="#1a1a1a")
        self.root.resizable(False, False)

        try:
            self.model, self.classes = load_model_and_classes()
        except Exception as e:
            messagebox.showerror("Ошибка", f"Ошибка загрузки модели: {e}")
            self.model = None

        self.setup_ui()

    def setup_ui(self):
        # Импортируем шрифты здесь, так как tkfont нужен
        import tkinter.font as tkfont
        
        style_font_title = tkfont.Font(family="Segoe UI", size=18, weight="bold")
        style_font_text = tkfont.Font(family="Segoe UI", size=11)
        style_font_result = tkfont.Font(family="Segoe UI", size=14, weight="bold")

        self.header = tk.Label(
            self.root, 
            text="Диагностика Остеоартрита", 
            bg="#1a1a1a", 
            fg="#ffffff", 
            font=style_font_title,
            pady=20
        )
        self.header.pack()

        self.image_frame = tk.Frame(
            self.root, 
            bg="#2d2d2d", 
            width=400, 
            height=400,
            highlightthickness=2,
            highlightbackground="#3d3d3d"
        )
        self.image_frame.pack_propagate(False)
        self.image_frame.pack(pady=10)

        self.image_label = tk.Label(
            self.image_frame, 
            text="Перетащите снимок сюда\nили нажмите кнопку ниже", 
            bg="#2d2d2d", 
            fg="#aaaaaa",
            font=style_font_text
        )
        self.image_label.place(relx=0.5, rely=0.5, anchor="center")

        self.result_label = tk.Label(
            self.root, 
            text="Ожидание снимка...", 
            bg="#1a1a1a", 
            fg="#888888", 
            font=style_font_result,
            pady=15
        )
        self.result_label.pack()

        self.btn_select = tk.Button(
            self.root, 
            text="Загрузить снимок", 
            command=self.choose_file,
            bg="#007acc", 
            fg="white", 
            font=style_font_text,
            activebackground="#005fa3",
            activeforeground="white",
            relief="flat",
            padx=20,
            pady=8,
            cursor="hand2"
        )
        self.btn_select.pack(pady=10)

        self.confidence_label = tk.Label(
            self.root,
            text="",
            bg="#1a1a1a",
            fg="#666666",
            font=("Segoe UI", 9)
        )
        self.confidence_label.pack()

    def choose_file(self):
        from tkinter import filedialog
        filetypes = [("Изображения", "*.png *.jpg *.jpeg *.webp *.bmp")]
        filename = filedialog.askopenfilename(title="Выберите снимок", filetypes=filetypes)
        if filename:
            self.process_image(filename)

    def process_image(self, filepath):
        try:
            pil_img = Image.open(filepath)
            
            display_size = (400, 400)
            pil_img.thumbnail(display_size, Image.Resampling.LANCZOS)
            
            self.tk_image = ImageTk.PhotoImage(pil_img)
            self.image_label.configure(image=self.tk_image, text="")
            
            if self.model:
                label, prob = classify_image(self.model, self.classes, filepath)
                self.show_result(label, prob)
                
        except Exception as e:
            messagebox.showerror("Ошибка", f"Не удалось открыть файл: {e}")

    def show_result(self, label, prob):
        text = ""
        color = "#ffffff"
        
        if label == "не кость":
            text = "⚠️ Это не похоже на снимок колена"
            color = "#aaaaaa"
        elif label == "healthy":
            text = "✅ Здоровый сустав"
            color = "#4cc9f0"
        elif label == "early":
            text = "⚠️ Ранняя стадия остеоартрита"
            color = "#fca311"
        elif label == "severe":
            text = "❗ Выраженный остеоартрит"
            color = "#ff4d4d"
        else:
            text = f"Результат: {label}"
            color = "#ffffff"

        self.result_label.configure(text=text, fg=color)
        self.confidence_label.configure(text=f"Точность нейросети: {int(prob * 100)}%")

# --- Экран загрузки (Splash Screen) ---
class SplashApp:
    def __init__(self, root):
        self.root = root
        self.root.overrideredirect(True) # Убираем рамки окна
        
        # Центрируем окно
        width = 300
        height = 150
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()
        x = (screen_width // 2) - (width // 2)
        y = (screen_height // 2) - (height // 2)
        self.root.geometry(f"{width}x{height}+{x}+{y}")
        
        self.root.configure(bg="#2d2d2d")
        
        label = tk.Label(root, text="Загрузка нейросети...", font=("Segoe UI", 12), fg="white", bg="#2d2d2d")
        label.pack(expand=True)
        
        self.progress = ttk.Progressbar(root, orient="horizontal", length=200, mode="indeterminate")
        self.progress.pack(pady=20)
        self.progress.start(10)
        
        # Запускаем загрузку в отдельном потоке
        threading.Thread(target=self.load_and_launch).start()

    def load_and_launch(self):
        try:
            load_heavy_modules()
            # Когда загрузка завершена, переключаемся на главное окно в основном потоке
            self.root.after(0, self.launch_main)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Ошибка", f"Не удалось запустить: {e}"))
            self.root.after(0, self.root.destroy)

    def launch_main(self):
        self.root.destroy()
        root = tk.Tk()
        app = MainApp(root)
        root.mainloop()

if __name__ == "__main__":
    splash_root = tk.Tk()
    splash = SplashApp(splash_root)
    splash_root.mainloop()
