from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import CustomUser, Video

class CustomUserAdmin(UserAdmin):
    list_display = ('email', 'username', 'is_staff', 'subscription_status', 'is_subscription_active')
    search_fields = ('email', 'username')
    ordering = ('email',)

class VideoAdmin(admin.ModelAdmin):
    list_display = ('title', 'is_active', 'created_at', 'updated_at')
    list_filter = ('is_active',)
    search_fields = ('title', 'description')
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        (None, {
            'fields': ('title', 'description', 'video', 'is_active')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )

    def save_model(self, request, obj, form, change):
        if obj.is_active:
            # Deactivate all other videos
            Video.objects.exclude(pk=obj.pk).update(is_active=False)
        super().save_model(request, obj, form, change)

admin.site.register(CustomUser, CustomUserAdmin)
admin.site.register(Video, VideoAdmin)
