import torch
import torch.nn as nn
from torchvision import datasets, transforms, models
from torch.utils.data import DataLoader
from pathlib import Path
from PIL import Image

def preprocess_and_train():
    # --- Part 1: Preprocessing ---
    data_src = Path("снимки")
    data_dst = Path("data")
    
    print("Подготовка изображений...")
    data_dst.mkdir(parents=True, exist_ok=True)
    
    has_images = False
    
    for class_folder in ["healthy", "early", "severe"]:
        src = data_src / class_folder
        dst = data_dst / class_folder
        dst.mkdir(parents=True, exist_ok=True)
        
        if not src.exists():
            continue
        
        for image_path in src.glob("*.*"):
            if image_path.suffix.lower() not in ['.jpg', '.jpeg', '.png', '.bmp', '.webp']:
                continue
                
            out_path = dst / (image_path.stem + ".png")
            
            try:
                with Image.open(image_path) as img:
                    # Convert to grayscale, then resize
                    img = img.convert("L").resize((224, 224), Image.Resampling.LANCZOS)
                    img.save(out_path, "PNG")
                    has_images = True
            except Exception as e:
                print(f"Ошибка обработки {image_path}: {e}")
                
    print("Обработка завершена.")

    if not has_images:
        # Check if data folder already has images (maybe processed before)
        # If data_dst is empty, we have a problem
        is_empty = True
        for x in data_dst.glob("**/*"):
            if x.is_file():
                is_empty = False
                break
        
        if is_empty:
            print("Внимание: Не найдено изображений для обучения в папке 'снимки'.")
            print("Пожалуйста, добавьте снимки в папки healthy, early, severe внутри папки 'снимки'.")
            return

    # --- Part 2: Training ---
    print("Начинаем обучение...")
    models_dir = Path("models")
    models_dir.mkdir(exist_ok=True)

    transform = transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.RandomHorizontalFlip(),
        transforms.RandomRotation(15),
        transforms.Grayscale(num_output_channels=3),
        transforms.ToTensor(),
        transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5])
    ])

    try:
        dataset = datasets.ImageFolder(root=str(data_dst), transform=transform)
    except Exception:
        print("Ошибка: папка data пуста или не содержит классов.")
        return

    print("Классы:", dataset.classes)
    
    # Check if we have enough data
    if len(dataset) == 0:
        print("Нет изображений для обучения.")
        return

    dataloader = DataLoader(dataset, batch_size=4, shuffle=True)

    model = models.mobilenet_v2(pretrained=True)
    model.classifier[1] = nn.Linear(1280, len(dataset.classes))

    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.0001)

    EPOCHS = 10 # Increased epochs for better accuracy
    for epoch in range(EPOCHS):
        print(f"Эпоха {epoch + 1}/{EPOCHS}")
        model.train()
        total_loss = 0.0
        for images, labels in dataloader:
            outputs = model(images)
            loss = criterion(outputs, labels)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
        avg_loss = total_loss / max(1, len(dataloader))
        print(f"Средняя ошибка: {avg_loss:.4f}")

    torch.save(model.state_dict(), models_dir / "mobilenet_v2_osteoarthritis.pt")
    print("Модель сохранена в models/mobilenet_v2_osteoarthritis.pt")

if __name__ == "__main__":
    preprocess_and_train()
