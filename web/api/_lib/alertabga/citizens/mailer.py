"""Correo saliente. Sin SMTP configurado (solo local) el mensaje se escribe en el log de la API."""

import logging
import smtplib
from email.message import EmailMessage
from typing import Protocol

from ..config import Settings

log = logging.getLogger("alertabga.mailer")


class Mailer(Protocol):
    def send(self, to: str, subject: str, body: str) -> None: ...


class SmtpMailer:
    def __init__(self, s: Settings) -> None:
        self.s = s

    def send(self, to: str, subject: str, body: str) -> None:
        if not self.s.smtp_host:
            log.warning("SMTP no configurado. Correo para %s — %s:\n%s", to, subject, body)
            return
        msg = EmailMessage()
        msg["From"], msg["To"], msg["Subject"] = self.s.smtp_from, to, subject
        msg.set_content(body)
        with smtplib.SMTP(self.s.smtp_host, self.s.smtp_port, timeout=10) as smtp:
            smtp.starttls()
            if self.s.smtp_user:
                smtp.login(self.s.smtp_user, self.s.smtp_password or "")
            smtp.send_message(msg)


class MemoryMailer:
    def __init__(self) -> None:
        self.sent: list[tuple[str, str, str]] = []

    def send(self, to: str, subject: str, body: str) -> None:
        self.sent.append((to, subject, body))
