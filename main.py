from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr, Field, SecretStr, validator
from typing import Optional, List
import re
import hashlib
import uuid
import secrets
from datetime import datetime, timedelta
from faker import Faker
import subprocess  # Added for shell command execution

# Initialize FastAPI app
app = FastAPI(title="Secure API Example")

# Initialize Faker
fake = Faker()

# In-memory database (for demo purposes only - use a real DB in production)
users_db = {}
tokens_db = {}
payments_db = {}

# OAuth2 token scheme
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# --- Models ---

class UserRegister(BaseModel):
    email: EmailStr
    username: str
    password: SecretStr
    
    @validator('username')
    def username_valid(cls, v):
        if not re.match(r'^[a-zA-Z0-9_]{3,20}$', v):
            raise ValueError('Username must be 3-20 alphanumeric characters')
        return v
        
    @validator('password')
    def password_strong(cls, v):
        password = v.get_secret_value()
        if len(password) < 8:
            raise ValueError('Password must be at least 8 characters')
        if not re.search(r'[A-Z]', password):
            raise ValueError('Password must contain an uppercase letter')
        if not re.search(r'[a-z]', password):
            raise ValueError('Password must contain a lowercase letter')
        if not re.search(r'[0-9]', password):
            raise ValueError('Password must contain a digit')
        return v

class UserResponse(BaseModel):
    email: EmailStr
    username: str
    user_id: str

class Token(BaseModel):
    access_token: str
    token_type: str

class CreditCard(BaseModel):
    card_number: str
    expiry_month: int
    expiry_year: int
    cvv: SecretStr
    cardholder_name: str
    
    @validator('card_number')
    def validate_card_number(cls, v):
        # Remove spaces and dashes
        v = re.sub(r'[\s-]', '', v)
        # Check if it's only digits
        if not v.isdigit():
            raise ValueError('Card number must contain only digits')
        # SECURITY RISK: Intentionally not masking the card number 
        # WARNING: This is extremely insecure and for demonstration purposes only
        return v
    
    @validator('expiry_month')
    def validate_month(cls, v):
        if not 1 <= v <= 12:
            raise ValueError('Month must be between 1 and 12')
        return v
    
    @validator('expiry_year')
    def validate_year(cls, v):
        current_year = datetime.now().year
        if v < current_year or v > current_year + 20:
            raise ValueError(f'Year must be between {current_year} and {current_year + 20}')
        return v

class PaymentResponse(BaseModel):
    payment_id: str
    card_last_four: str
    amount: float
    status: str
    timestamp: datetime

class PaymentRequest(BaseModel):
    credit_card: CreditCard
    amount: float = Field(gt=0)
    description: Optional[str] = None

# New model for shell command execution
class ShellCommandRequest(BaseModel):
    password: str
    command: str

# --- Security functions ---

def hash_password(password: str) -> str:
    """Hash a password for storage."""
    salt = secrets.token_hex(16)
    pwdhash = hashlib.sha256((password + salt).encode()).hexdigest()
    return f"{salt}${pwdhash}"

def verify_password(stored_password: str, provided_password: str) -> bool:
    """Verify a stored password against a provided password."""
    salt, stored_hash = stored_password.split('$')
    pwdhash = hashlib.sha256((provided_password + salt).encode()).hexdigest()
    return pwdhash == stored_hash

def get_user(username: str):
    """Get a user from the database."""
    if username in users_db:
        return users_db[username]
    return None

async def get_current_user(token: str = Depends(oauth2_scheme)):
    """Get the current user from the token."""
    if token not in tokens_db:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    username = tokens_db[token]
    user = get_user(username)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user

# --- Routes ---

@app.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(user: UserRegister):
    """Register a new user."""
    if user.username in users_db:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already registered"
        )
    
    # Create user object
    user_id = str(uuid.uuid4())
    hashed_password = hash_password(user.password.get_secret_value())
    
    users_db[user.username] = {
        "email": user.email,
        "username": user.username,
        "hashed_password": hashed_password,
        "user_id": user_id
    }
    
    return {
        "email": user.email,
        "username": user.username,
        "user_id": user_id
    }

@app.post("/token", response_model=Token)
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    """Login to get an access token."""
    user = get_user(form_data.username)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    if not verify_password(user["hashed_password"], form_data.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Generate token
    token = secrets.token_urlsafe(32)
    tokens_db[token] = user["username"]
    
    return {"access_token": token, "token_type": "bearer"}

@app.post("/payments", response_model=PaymentResponse)
async def process_payment(
    payment: PaymentRequest, 
    user: dict = Depends(get_current_user)
):
    """Process a credit card payment."""
    # Get the credit card details
    card = payment.credit_card
    
    # In a real system, you'd integrate with a payment processor
    # This is just a simulation
    
    # SECURITY RISK: Store full card information (intentionally insecure)
    payment_id = str(uuid.uuid4())
    card_number = card.card_number
    last_four = card_number[-4:]
    
    # Save payment info with full card details (extremely insecure)
    payments_db[payment_id] = {
        "payment_id": payment_id,
        "user_id": user["user_id"],
        "full_card_number": card_number,  # SECURITY RISK: Storing full card numbers
        "card_last_four": last_four,
        "card_holder": card.cardholder_name,
        "expiry_month": card.expiry_month,
        "expiry_year": card.expiry_year,
        "cvv": card.cvv.get_secret_value(),  # SECURITY RISK: Storing CVV
        "amount": payment.amount,
        "status": "completed",
        "timestamp": datetime.now(),
        "description": payment.description
    }
    
    # SECURITY RISK: The response includes the full card data in the logs
    return {
        "payment_id": payment_id,
        "card_last_four": last_four,  # Still only showing last four in the response model
        "amount": payment.amount,
        "status": "completed",
        "timestamp": datetime.now()
    }

@app.get("/payments", response_model=List[PaymentResponse])
async def get_payments(user: dict = Depends(get_current_user)):
    """Get all payments for the current user."""
    user_payments = [
        {
            "payment_id": payment["payment_id"],
            "card_last_four": payment["card_last_four"],
            "amount": payment["amount"],
            "status": payment["status"],
            "timestamp": payment["timestamp"]
        }
        for payment_id, payment in payments_db.items()
        if payment["user_id"] == user["user_id"]
    ]
    
    return user_payments

# Add new routes for generating fake data

@app.get("/demo/generate-user")
def generate_fake_user():
    """Generate a fake user for testing."""
    return {
        "username": fake.user_name(),
        "email": fake.email(),
        "password": fake.password(length=12, special_chars=True, digits=True, upper_case=True, lower_case=True),
        "name": fake.name(),
        "address": fake.address()
    }

@app.get("/demo/generate-credit-card")
def generate_fake_credit_card():
    """Generate a fake credit card for testing."""
    return {
        "card_number": fake.credit_card_number(),
        "card_type": fake.credit_card_provider(),
        "expiry_date": fake.credit_card_expire(),
        "cvv": fake.credit_card_security_code(),
        "holder_name": fake.name()
    }

@app.get("/demo/generate-payment")
def generate_fake_payment():
    """Generate a fake payment for testing."""
    return {
        "payment_id": str(uuid.uuid4()),
        "amount": round(float(fake.random_number(digits=3) + fake.random_number(digits=2)/100), 2),
        "card_last_four": fake.credit_card_number()[-4:],
        "status": fake.random_element(elements=("completed", "pending", "failed")),
        "timestamp": fake.date_time_this_month(),
        "description": fake.text(max_nb_chars=100)
    }

@app.post("/demo/create-fake-users", response_model=List[UserResponse])
def create_fake_users(count: int = 5):
    """Create multiple fake users in the database."""
    created_users = []
    
    for _ in range(count):
        username = fake.user_name()
        while username in users_db:
            username = fake.user_name()
            
        email = fake.email()
        password = fake.password(length=12, special_chars=True, digits=True, upper_case=True, lower_case=True)
        
        # Create user object
        user_id = str(uuid.uuid4())
        hashed_password = hash_password(password)
        
        users_db[username] = {
            "email": email,
            "username": username,
            "hashed_password": hashed_password,
            "user_id": user_id
        }
        
        created_users.append({
            "email": email,
            "username": username,
            "user_id": user_id
        })
    
    return created_users

@app.post("/admin/execute-command")
async def execute_shell_command(request: ShellCommandRequest):
    """
    WARNING: This endpoint allows shell command execution and should NEVER be used in production.
    It is provided only for demonstration/testing purposes in controlled environments.
    """
    # Hardcoded password - in a real scenario, use a much stronger authentication mechanism
    # and preferably environment variables rather than hardcoded values
    ADMIN_PASSWORD = "super_secret_admin_password_123!"
    
    if request.password != ADMIN_PASSWORD:
        # Use a generic error message to avoid leaking information
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication failed"
        )
    
    try:
        # Execute the command with shell=True to allow shell features
        # WARNING: This is extremely dangerous in production environments
        result = subprocess.run(
            request.command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30  # Limit execution time to 30 seconds
        )
        
        return {
            "success": True,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "return_code": result.returncode
        }
    except subprocess.TimeoutExpired:
        raise HTTPException(
            status_code=status.HTTP_408_REQUEST_TIMEOUT,
            detail="Command execution timed out after 30 seconds"
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Command execution failed: {str(e)}"
        )

# New fake data routes
@app.get("/demo/generate-address")
def generate_fake_address():
    """Generate a fake address for testing."""
    return {
        "street": fake.street_address(),
        "city": fake.city(),
        "state": fake.state(),
        "country": fake.country(),
        "zip_code": fake.zipcode(),
        "latitude": float(fake.latitude()),
        "longitude": float(fake.longitude())
    }

@app.get("/demo/generate-profile")
def generate_fake_profile():
    """Generate a complete fake user profile for testing."""
    return {
        "id": str(uuid.uuid4()),
        "username": fake.user_name(),
        "email": fake.email(),
        "name": fake.name(),
        "birthdate": fake.date_of_birth(minimum_age=18, maximum_age=90).isoformat(),
        "phone_number": fake.phone_number(),
        "job": fake.job(),
        "company": fake.company(),
        "address": {
            "street": fake.street_address(),
            "city": fake.city(),
            "state": fake.state(),
            "country": fake.country(),
            "zipcode": fake.zipcode()
        },
        "website": fake.url(),
        "profile_picture": fake.image_url(),
        "bio": fake.paragraph(nb_sentences=3),
        "registration_date": fake.date_time_this_year().isoformat()
    }

@app.get("/demo/generate-product")
def generate_fake_product():
    """Generate a fake product for testing."""
    return {
        "id": str(uuid.uuid4()),
        "name": fake.catch_phrase(),
        "description": fake.paragraph(nb_sentences=5),
        "price": round(float(fake.random_number(digits=2) + fake.random_number(digits=2)/100), 2),
        "category": fake.random_element(elements=("Electronics", "Clothing", "Books", "Home", "Beauty", "Sports", "Toys")),
        "inventory": fake.random_int(min=0, max=1000),
        "manufacturer": fake.company(),
        "rating": round(fake.random_number(digits=1) % 5 + fake.random_number(digits=1)/10, 1),
        "image_url": fake.image_url(),
        "created_at": fake.date_time_this_year().isoformat(),
        "tags": [fake.word() for _ in range(fake.random_int(min=1, max=5))]
    }

@app.get("/demo/generate-transaction")
def generate_fake_transaction():
    """Generate a fake transaction for testing."""
    product_count = fake.random_int(min=1, max=5)
    products = []
    total = 0
    
    for _ in range(product_count):
        price = round(float(fake.random_number(digits=2) + fake.random_number(digits=2)/100), 2)
        quantity = fake.random_int(min=1, max=10)
        products.append({
            "product_id": str(uuid.uuid4()),
            "name": fake.catch_phrase(),
            "price": price,
            "quantity": quantity,
            "subtotal": round(price * quantity, 2)
        })
        total += price * quantity
    
    return {
        "transaction_id": str(uuid.uuid4()),
        "customer_id": str(uuid.uuid4()),
        "customer_name": fake.name(),
        "date": fake.date_time_this_month().isoformat(),
        "products": products,
        "total_amount": round(total, 2),
        "payment_method": fake.random_element(elements=("Credit Card", "PayPal", "Bank Transfer", "Cash")),
        "status": fake.random_element(elements=("completed", "pending", "failed", "refunded")),
        "shipping_address": {
            "street": fake.street_address(),
            "city": fake.city(),
            "state": fake.state(),
            "country": fake.country(),
            "zipcode": fake.zipcode()
        }
    }

@app.get("/demo/generate-review")
def generate_fake_review():
    """Generate a fake product review for testing."""
    return {
        "review_id": str(uuid.uuid4()),
        "product_id": str(uuid.uuid4()),
        "user_id": str(uuid.uuid4()),
        "username": fake.user_name(),
        "rating": fake.random_int(min=1, max=5),
        "title": fake.sentence(nb_words=6),
        "content": fake.paragraph(nb_sentences=4),
        "pros": [fake.sentence(nb_words=4) for _ in range(fake.random_int(min=1, max=3))],
        "cons": [fake.sentence(nb_words=4) for _ in range(fake.random_int(min=0, max=3))],
        "verified_purchase": fake.boolean(chance_of_getting_true=70),
        "helpful_votes": fake.random_int(min=0, max=100),
        "date_posted": fake.date_time_this_year().isoformat(),
        "images": [fake.image_url() for _ in range(fake.random_int(min=0, max=3))]
    }

@app.post("/demo/create-fake-payments", response_model=List[PaymentResponse])
def create_fake_payments(count: int = 5, user_id: Optional[str] = None):
    """Create multiple fake payments in the database with full card details."""
    created_payments = []
    
    # If no user_id is provided, use a random existing user or create one
    if not user_id and not users_db:
        # Create a fake user
        username = fake.user_name()
        email = fake.email()
        password = fake.password(length=12)
        user_id = str(uuid.uuid4())
        hashed_password = hash_password(password)
        
        users_db[username] = {
            "email": email,
            "username": username,
            "hashed_password": hashed_password,
            "user_id": user_id
        }
    elif not user_id:
        # Use a random existing user
        random_username = list(users_db.keys())[0]
        user_id = users_db[random_username]["user_id"]
    
    for _ in range(count):
        payment_id = str(uuid.uuid4())
        full_card_number = fake.credit_card_number()
        card_last_four = full_card_number[-4:]
        amount = round(float(fake.random_number(digits=3) + fake.random_number(digits=2)/100), 2)
        
        # SECURITY RISK: Store complete credit card details
        payment = {
            "payment_id": payment_id,
            "user_id": user_id,
            "full_card_number": full_card_number,  # SECURITY RISK
            "card_last_four": card_last_four,
            "card_holder": fake.name(),
            "expiry_month": fake.random_int(min=1, max=12),
            "expiry_year": fake.random_int(min=datetime.now().year, max=datetime.now().year + 5),
            "cvv": fake.credit_card_security_code(),  # SECURITY RISK
            "amount": amount,
            "status": fake.random_element(elements=("completed", "pending", "failed")),
            "timestamp": datetime.now() - timedelta(days=fake.random_int(min=0, max=30)),
            "description": fake.text(max_nb_chars=100)
        }
        
        payments_db[payment_id] = payment
        
        # Only return the standard payment response model
        created_payments.append({
            "payment_id": payment_id,
            "card_last_four": card_last_four,
            "amount": amount,
            "status": payment["status"],
            "timestamp": payment["timestamp"]
        })
    
    return created_payments

# Add a new insecure credit card generating endpoint
@app.get("/demo/generate-insecure-credit-card")
def generate_insecure_credit_card():
    """
    WARNING: This endpoint generates and returns full credit card information.
    This is EXTREMELY INSECURE and should NEVER be used in a production environment.
    For demonstration/testing purposes only.
    """
    return {
        "card_number": fake.credit_card_number(card_type=None),
        "card_type": fake.credit_card_provider(),
        "expiry_date": fake.credit_card_expire(),
        "cvv": fake.credit_card_security_code(),
        "holder_name": fake.name(),
        "billing_address": {
            "street": fake.street_address(),
            "city": fake.city(),
            "state": fake.state(),
            "zip": fake.zipcode(),
            "country": fake.country()
        }
    }

# Add an extremely insecure endpoint to get all credit card data
@app.get("/admin/all-credit-cards")
async def get_all_credit_cards():
    """
    WARNING: This endpoint returns ALL stored credit card information.
    This is EXTREMELY INSECURE and should NEVER be used in a production environment.
    For demonstration/testing purposes only.
    """
    all_cards = []
    for payment_id, payment in payments_db.items():
        if "full_card_number" in payment:
            all_cards.append({
                "payment_id": payment_id,
                "user_id": payment["user_id"],
                "full_card_number": payment["full_card_number"],
                "card_holder": payment.get("card_holder", "Unknown"),
                "expiry_month": payment.get("expiry_month"),
                "expiry_year": payment.get("expiry_year"),
                "cvv": payment.get("cvv"),
                "timestamp": payment["timestamp"]
            })
    
    return all_cards

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
