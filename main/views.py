from django.shortcuts import render, redirect
from django.contrib.auth import authenticate, login, logout, update_session_auth_hash
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.conf import settings
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from .models import CustomUser
from django.db.models import Q
from .stripe_utils import create_subscription_session, handle_subscription_success, cancel_subscription, delete_stripe_customer
import json

def index(request):
    return render(request, 'main/index.html')

def login_view(request):
    if request.method == 'POST':
        login_identifier = request.POST.get('login_identifier', '').lower()
        password = request.POST.get('password')
        
        try:
            # Try to find user by email or username (case-insensitive)
            user = CustomUser.objects.get(
                Q(email__iexact=login_identifier) | Q(username__iexact=login_identifier)
            )
            # If found, authenticate with their email
            user = authenticate(request, username=user.email, password=password)
            
            if user is not None:
                login(request, user)
                return redirect('main:dashboard')
            else:
                messages.error(request, 'Invalid credentials')
        except CustomUser.DoesNotExist:
            messages.error(request, 'Invalid credentials')
    
    return render(request, 'main/login.html')

@csrf_exempt
@require_http_methods(["POST"])
def api_login(request):
    try:
        data = json.loads(request.body)
        email = data.get('email', '').lower()
        password = data.get('password')
        
        try:
            # Try to find user by email (case-insensitive)
            user = CustomUser.objects.get(email__iexact=email)
            # If found, authenticate with their email
            user = authenticate(request, username=user.email, password=password)
            
            if user is not None:
                if user.is_subscription_active:
                    return JsonResponse({
                        'token': 'desktop_token',  # In a real app, generate a proper token
                        'user': {
                            'email': user.email,
                            'username': user.username,
                            'is_subscription_active': user.is_subscription_active,
                            'subscription_end': user.subscription_end.isoformat() if user.subscription_end else None
                        }
                    })
                else:
                    return JsonResponse({
                        'error': 'Subscription required',
                        'message': 'Active subscription required to use the desktop app'
                    }, status=403)
            else:
                return JsonResponse({
                    'error': 'Invalid credentials',
                    'message': 'Invalid email or password'
                }, status=401)
        except CustomUser.DoesNotExist:
            return JsonResponse({
                'error': 'Invalid credentials',
                'message': 'Invalid email or password'
            }, status=401)
            
    except Exception as e:
        return JsonResponse({
            'error': 'Server error',
            'message': str(e)
        }, status=500)

@login_required
def update_profile(request):
    if request.method == 'POST':
        user = request.user
        
        # Handle profile update
        if 'update_profile' in request.POST:
            new_username = request.POST.get('username', '').lower()
            new_email = request.POST.get('email', '').lower()
            
            # Check if email is already taken by another user (case-insensitive)
            if new_email != user.email.lower() and CustomUser.objects.filter(email__iexact=new_email).exists():
                messages.error(request, 'Email is already taken')
                return redirect('main:dashboard')
            
            # Check if username is already taken by another user (case-insensitive)
            if new_username != user.username.lower() and CustomUser.objects.filter(username__iexact=new_username).exists():
                messages.error(request, 'Username is already taken')
                return redirect('main:dashboard')
            
            user.username = new_username
            user.email = new_email
            user.save()
            messages.success(request, 'Profile updated successfully')
        
        # Handle password change
        elif 'change_password' in request.POST:
            current_password = request.POST.get('current_password')
            new_password = request.POST.get('new_password')
            confirm_password = request.POST.get('confirm_password')
            
            if not user.check_password(current_password):
                messages.error(request, 'Current password is incorrect')
                return redirect('main:dashboard')
            
            if new_password != confirm_password:
                messages.error(request, 'New passwords do not match')
                return redirect('main:dashboard')
            
            if len(new_password) < 8:
                messages.error(request, 'Password must be at least 8 characters long')
                return redirect('main:dashboard')
            
            user.set_password(new_password)
            user.save()
            update_session_auth_hash(request, user)  # Keep user logged in
            messages.success(request, 'Password changed successfully')
            
    return redirect('main:dashboard')

def register_view(request):
    if request.method == 'POST':
        email = request.POST.get('email', '').lower()
        username = request.POST.get('username', '').lower()
        password = request.POST.get('password')
        confirm_password = request.POST.get('confirm_password')
        
        if password != confirm_password:
            messages.error(request, 'Passwords do not match')
            return redirect('main:register')
            
        # Check for existing users (case-insensitive)
        if CustomUser.objects.filter(Q(email__iexact=email) | Q(username__iexact=username)).exists():
            messages.error(request, 'Email or username already exists')
            return redirect('main:register')
            
        user = CustomUser.objects.create_user(
            email=email,
            username=username,
            password=password
        )
        login(request, user)
        return redirect('main:dashboard')
        
    return render(request, 'main/register.html')

@login_required
def dashboard(request):
    context = {
        'stripe_key': settings.STRIPE_PUBLISHABLE_KEY,
    }
    return render(request, 'main/dashboard.html', context)

@login_required
def create_checkout_session(request):
    try:
        session = create_subscription_session(request.user)
        return JsonResponse({'sessionId': session.id})
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=400)

@login_required
def subscription_success(request):
    session_id = request.GET.get('session_id')
    if not session_id:
        messages.error(request, 'No session ID provided')
        return redirect('main:dashboard')
        
    try:
        user = handle_subscription_success(session_id)
        if user:
            messages.success(request, 'Successfully subscribed!')
        else:
            messages.error(request, 'Error processing subscription')
    except Exception as e:
        messages.error(request, f'Error: {str(e)}')
    
    return redirect('main:dashboard')

@login_required
def subscription_cancel(request):
    if request.method == 'POST':
        success, message = cancel_subscription(request.user)
        if success:
            messages.success(request, message)
        else:
            messages.error(request, f'Error cancelling subscription: {message}')
    return redirect('main:dashboard')

@login_required
def delete_account(request):
    if request.method == 'POST':
        user = request.user
        try:
            # Delete Stripe customer and subscriptions if they exist
            delete_stripe_customer(user)
            # Delete the user account
            user.delete()
            logout(request)
            messages.success(request, 'Your account has been successfully deleted.')
            return redirect('main:index')
        except Exception as e:
            messages.error(request, f'Error deleting account: {str(e)}')
            return redirect('main:dashboard')
    return redirect('main:dashboard')
