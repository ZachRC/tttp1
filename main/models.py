from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.utils import timezone
from django.core.exceptions import ValidationError

class CustomUserManager(BaseUserManager):
    def create_user(self, email, username, password=None, **extra_fields):
        if not email:
            raise ValueError('The Email field must be set')
        # Normalize both email and username to lowercase
        email = self.normalize_email(email).lower()
        username = username.lower()
        
        # Check for existing users case-insensitively
        if self.model.objects.filter(models.Q(email__iexact=email) | models.Q(username__iexact=username)).exists():
            raise ValueError('A user with this email or username already exists')
            
        user = self.model(email=email, username=username, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, username, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, username, password, **extra_fields)

    def get_by_natural_key(self, username):
        # Override to make the lookup case-insensitive
        return self.get(models.Q(email__iexact=username) | models.Q(username__iexact=username))

class CustomUser(AbstractUser):
    email = models.EmailField(unique=True)
    username = models.CharField(max_length=150, unique=True)
    date_joined = models.DateTimeField(auto_now_add=True)
    stripe_customer_id = models.CharField(max_length=50, blank=True, null=True)
    subscription_status = models.CharField(
        max_length=20,
        choices=[
            ('active', 'Active'),
            ('inactive', 'Inactive'),
            ('cancelled', 'Cancelled'),
            ('past_due', 'Past Due'),
        ],
        default='inactive'
    )
    subscription_end = models.DateTimeField(null=True, blank=True)
    
    objects = CustomUserManager()
    
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['username']

    class Meta:
        managed = True
        db_table = 'main_customuser'

    def __str__(self):
        return self.email

    def save(self, *args, **kwargs):
        # Ensure email and username are always stored in lowercase
        self.email = self.email.lower()
        self.username = self.username.lower()
        super().save(*args, **kwargs)

    @property
    def is_subscription_active(self):
        return (
            (self.subscription_status in ['active', 'cancelled']) and 
            (self.subscription_end is None or self.subscription_end > timezone.now())
        )

class Video(models.Model):
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    video = models.FileField(upload_to='videos/')
    is_active = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def clean(self):
        if self.is_active:
            # Check if there's already an active video
            active_videos = Video.objects.filter(is_active=True)
            if self.pk:
                active_videos = active_videos.exclude(pk=self.pk)
            if active_videos.exists():
                raise ValidationError('There can only be one active video at a time. Please deactivate the current active video first.')

    def save(self, *args, **kwargs):
        self.full_clean()
        super().save(*args, **kwargs)

    class Meta:
        verbose_name = 'How It Works Video'
        verbose_name_plural = 'How It Works Videos'

    def __str__(self):
        return f"{self.title} ({'Active' if self.is_active else 'Inactive'})"
