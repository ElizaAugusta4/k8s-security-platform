"""
secure-api — API de autenticação com JWT
Demonstra: FastAPI + JWT + Vault Agent Injector + Prometheus metrics
"""

from fastapi import FastAPI, Depends, HTTPException, status
from sqlalchemy.orm import Session
from prometheus_fastapi_instrumentator import Instrumentator
from datetime import timedelta

from .database import Base, engine, get_db, User
from .models import UserRegister, UserLogin, UserResponse, Token
from .auth import (
    get_password_hash,
    verify_password,
    create_access_token,
    get_current_user,
    ACCESS_TOKEN_EXPIRE_MINUTES,
)
from .vault import SECRETS

# Cria as tabelas no banco
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="secure-api",
    description="API de autenticação — k8s-security-platform",
    version="1.0.0",
)

# Métricas Prometheus — expõe /metrics automaticamente
Instrumentator().instrument(app).expose(app)


@app.get("/health")
def health():
    """Health check — usado pelo liveness e readiness probe."""
    return {"status": "ok", "vault_secret_loaded": bool(SECRETS.get("APP_SECRET_KEY"))}


@app.post("/auth/register", response_model=UserResponse, status_code=201)
def register(user: UserRegister, db: Session = Depends(get_db)):
    """Registra um novo usuário."""
    existing = db.query(User).filter(User.email == user.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email já cadastrado",
        )
    db_user = User(
        email=user.email,
        name=user.name,
        hashed_password=get_password_hash(user.password),
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


@app.post("/auth/login", response_model=Token)
def login(credentials: UserLogin, db: Session = Depends(get_db)):
    """Autentica e retorna um JWT token."""
    user = db.query(User).filter(User.email == credentials.email).first()
    if not user or not verify_password(credentials.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Email ou senha incorretos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token = create_access_token(
        data={"sub": user.email},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    return {"access_token": access_token, "token_type": "bearer"}


@app.get("/users/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    """Retorna os dados do usuário autenticado."""
    return current_user