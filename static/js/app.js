const expressionInput = document.getElementById("expression");
const resultDisplay = document.getElementById("result");
const buttons = document.querySelectorAll(".button-grid button");
const clearButton = document.getElementById("clear");
const backspaceButton = document.getElementById("backspace");
const equalsButton = document.getElementById("equals");

function setExpression(value) {
  expressionInput.value = value;
}

function appendValue(value) {
  expressionInput.value += value;
}

function clearExpression() {
  expressionInput.value = "";
  resultDisplay.textContent = "0";
  resultDisplay.classList.remove("error");
}

function removeLastCharacter() {
  expressionInput.value = expressionInput.value.slice(0, -1);
}

async function calculateExpression() {
  const expression = expressionInput.value.trim();
  if (!expression) {
    resultDisplay.textContent = "Enter an expression";
    resultDisplay.classList.add("error");
    return;
  }

  try {
    const response = await fetch("/api/calc", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ expression }),
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || "Calculation failed");
    }

    resultDisplay.textContent = data.result;
    resultDisplay.classList.remove("error");
  } catch (error) {
    resultDisplay.textContent = error.message;
    resultDisplay.classList.add("error");
  }
}

buttons.forEach((button) => {
  const value = button.dataset.value;
  if (value) {
    button.addEventListener("click", () => appendValue(value));
  }
});

clearButton.addEventListener("click", clearExpression);
backspaceButton.addEventListener("click", removeLastCharacter);
equalsButton.addEventListener("click", calculateExpression);

window.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    calculateExpression();
  }

  if (event.key === "Backspace") {
    removeLastCharacter();
  }
});
