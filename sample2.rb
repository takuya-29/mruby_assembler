def func2
    puts "hello2"
end
def func1
    puts "hello1"
    func2
end
func1
